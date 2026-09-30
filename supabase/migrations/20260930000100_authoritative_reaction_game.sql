alter table public.games
  add column if not exists countdown_ends_at timestamptz,
  add column if not exists current_round_number integer not null default 0
    check (current_round_number between 0 and 10);

alter table public.rounds
  add column if not exists scheduled_at timestamptz,
  add column if not exists target_x double precision,
  add column if not exists target_y double precision;

create table if not exists public.game_scores (
  game_id uuid not null,
  room_id uuid not null,
  player_id uuid not null,
  score integer not null default 0 check (score between 0 and 10),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (game_id, player_id),
  foreign key (game_id, room_id) references public.games(id, room_id) on delete cascade,
  foreign key (player_id, room_id) references public.players(id, room_id)
);

alter table public.game_scores enable row level security;
create policy room_members_can_read_game_scores
  on public.game_scores for select to authenticated
  using (private.is_room_member(room_id));
revoke all on public.game_scores from public, anon, authenticated;
grant select on public.game_scores to authenticated;

create or replace function private.game_snapshot(p_room_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_game public.games%rowtype;
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  select * into v_room from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code)) for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if not exists (
    select 1 from private.player_sessions as ps
    join public.players as p on p.id = ps.player_id
    where ps.user_id = v_user_id and p.room_id = v_room.id and p.left_at is null
  ) then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;

  perform private.advance_game(p_room_code);
  select * into v_game from public.games
   where room_id = v_room.id order by game_number desc limit 1;
  if not found then raise exception using errcode = 'P0001', message = 'GAME_NOT_STARTED'; end if;

  return jsonb_build_object(
    'server_now', clock_timestamp(),
    'room', jsonb_build_object('id', v_room.id, 'code', v_room.code, 'host_player_id', v_room.host_player_id),
    'game', jsonb_build_object(
      'id', v_game.id, 'game_number', v_game.game_number, 'status', v_game.status,
      'started_at', v_game.started_at, 'countdown_ends_at', v_game.countdown_ends_at,
      'completed_at', v_game.completed_at, 'current_round_number', v_game.current_round_number
    ),
    'players', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'display_name', p.display_name, 'is_host', p.id = v_room.host_player_id
    ) order by p.joined_at, p.id) from public.players p
      where p.room_id = v_room.id and p.left_at is null), '[]'::jsonb),
    'round', (select jsonb_build_object(
      'id', r.id, 'round_number', r.round_number, 'status', r.status,
      'scheduled_at', r.scheduled_at, 'opened_at', r.opened_at, 'closes_at', r.closes_at,
      'target_x', r.target_x, 'target_y', r.target_y, 'winner_player_id', r.winner_player_id
    ) from public.rounds r where r.game_id = v_game.id
       and r.round_number = v_game.current_round_number),
    'leaderboard', coalesce((select jsonb_agg(jsonb_build_object(
      'player_id', gs.player_id, 'display_name', p.display_name, 'score', gs.score
    ) order by gs.score desc, p.joined_at, p.id)
      from public.game_scores gs join public.players p on p.id = gs.player_id
      where gs.game_id = v_game.id), '[]'::jsonb)
  );
end;
$$;

create or replace function private.advance_game(p_room_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_game public.games%rowtype;
  v_round public.rounds%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  select * into v_room from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code)) for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if not exists (
    select 1 from private.player_sessions ps join public.players p on p.id = ps.player_id
     where ps.user_id = v_user_id and p.room_id = v_room.id and p.left_at is null
  ) then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  select * into v_game from public.games where room_id = v_room.id
   order by game_number desc limit 1 for update;
  if not found or v_game.status in ('completed', 'cancelled') then return; end if;

  if v_game.status = 'countdown' and v_game.countdown_ends_at <= v_now then
    update public.games set status = 'active' where id = v_game.id;
  end if;
  if v_game.status not in ('countdown', 'active') then return; end if;
  select * into v_round from public.rounds
   where game_id = v_game.id and round_number = v_game.current_round_number for update;
  if not found then return; end if;

  if v_round.status = 'pending' and v_round.scheduled_at <= v_now and v_game.status = 'active' then
    update public.rounds set status = 'target_ready', opened_at = v_now,
      closes_at = v_now + interval '2500 milliseconds',
      target_x = 12 + random() * 76, target_y = 15 + random() * 70
      where id = v_round.id;
    return;
  end if;

  if v_round.status in ('resolved', 'expired') then
    if v_round.round_number >= 10 then
      update public.games set status = 'completed', completed_at = v_now where id = v_game.id;
      return;
    end if;
    if v_round.scheduled_at is null or v_round.scheduled_at <= v_now then
      update public.rounds set scheduled_at = v_now + interval '650 milliseconds'
       where id = v_round.id and scheduled_at is null;
      if v_round.scheduled_at is null then return; end if;
    end if;
    if v_round.scheduled_at <= v_now then
      insert into public.rounds(room_id, game_id, round_number, status, scheduled_at)
      values (v_room.id, v_game.id, v_round.round_number + 1, 'pending', v_now);
      update public.games set current_round_number = v_round.round_number + 1 where id = v_game.id;
    end if;
    return;
  end if;

  if v_round.status = 'target_ready' and v_round.closes_at <= v_now then
    update public.rounds set status = 'expired', resolved_at = v_now where id = v_round.id;
    if v_round.round_number >= 10 then
      update public.games set status = 'completed', completed_at = v_now where id = v_game.id;
    else
      insert into public.rounds(room_id, game_id, round_number, status, scheduled_at)
      values (v_room.id, v_game.id, v_round.round_number + 1, 'pending', v_now + interval '650 milliseconds');
      update public.games set current_round_number = v_round.round_number + 1 where id = v_game.id;
    end if;
  end if;
end;
$$;

create or replace function private.start_game(p_room_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_game public.games%rowtype;
  v_player_id uuid;
  v_game_number integer;
  v_start timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  select * into v_room from public.rooms where code = pg_catalog.upper(pg_catalog.btrim(p_room_code)) for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'expired' or v_room.expires_at <= v_start then
    raise exception using errcode = 'P0001', message = 'ROOM_EXPIRED';
  end if;
  select p.id into v_player_id from private.player_sessions ps join public.players p on p.id = ps.player_id
    where ps.user_id = v_user_id and p.room_id = v_room.id and p.left_at is null;
  if v_player_id is null then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  if v_player_id <> v_room.host_player_id then raise exception using errcode = 'P0001', message = 'HOST_ONLY'; end if;
  select * into v_game from public.games where room_id = v_room.id order by game_number desc limit 1 for update;
  if found and v_game.status not in ('completed', 'cancelled') then
    raise exception using errcode = 'P0001', message = 'GAME_ALREADY_STARTED';
  end if;
  if v_room.status = 'waiting' then perform private.prune_room(v_room.id); end if;
  if (select count(*) from public.players where room_id = v_room.id and left_at is null) < 2 then
    raise exception using errcode = 'P0001', message = 'NEED_MORE_PLAYERS';
  end if;
  select coalesce(max(game_number), 0) + 1 into v_game_number from public.games where room_id = v_room.id;
  insert into public.games(room_id, game_number, status, started_by_player_id, started_at,
      countdown_ends_at, current_round_number)
    values (v_room.id, v_game_number, 'countdown', v_player_id, v_start,
      v_start + interval '3 seconds', 1) returning * into v_game;
  insert into public.game_scores(game_id, room_id, player_id)
    select v_game.id, v_room.id, p.id from public.players p
     where p.room_id = v_room.id and p.left_at is null;
  insert into public.rounds(room_id, game_id, round_number, status, scheduled_at)
    values (v_room.id, v_game.id, 1, 'pending', v_game.countdown_ends_at);
  update public.rooms set status = 'started' where id = v_room.id;
  return private.game_snapshot(v_room.code);
end;
$$;

create or replace function private.submit_hit(p_room_code text, p_game_id uuid, p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_game public.games%rowtype;
  v_player_id uuid;
  v_round public.rounds%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  select * into v_room from public.rooms where code = pg_catalog.upper(pg_catalog.btrim(p_room_code)) for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  select p.id into v_player_id from private.player_sessions ps join public.players p on p.id = ps.player_id
   where ps.user_id = v_user_id and p.room_id = v_room.id and p.left_at is null;
  if v_player_id is null then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  select * into v_game from public.games where id = p_game_id and room_id = v_room.id for update;
  if not found or v_game.status <> 'active' or v_game.current_round_number < 1 then
    raise exception using errcode = 'P0001', message = 'STALE_TARGET';
  end if;
  select * into v_round from public.rounds where id = p_round_id and game_id = v_game.id for update;
  if not found or v_round.round_number <> v_game.current_round_number or v_round.status <> 'target_ready'
     or v_round.closes_at <= v_now then
    raise exception using errcode = 'P0001', message = 'STALE_TARGET';
  end if;
  update public.rounds set status = 'resolved', winner_player_id = v_player_id, resolved_at = v_now
   where id = v_round.id and status = 'target_ready' and closes_at > v_now;
  if not found then raise exception using errcode = 'P0001', message = 'STALE_TARGET'; end if;
  update public.game_scores set score = score + 1, updated_at = v_now
   where game_id = v_game.id and player_id = v_player_id;
  if v_round.round_number >= 10 then
    update public.games set status = 'completed', completed_at = v_now where id = v_game.id;
  else
    insert into public.rounds(room_id, game_id, round_number, status, scheduled_at)
      values (v_room.id, v_game.id, v_round.round_number + 1, 'pending', v_now + interval '650 milliseconds');
    update public.games set current_round_number = v_round.round_number + 1 where id = v_game.id;
  end if;
  return private.game_snapshot(v_room.code);
end;
$$;

create or replace function public.game_snapshot(p_room_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.game_snapshot(p_room_code); $$;
create or replace function public.advance_game(p_room_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.game_snapshot(p_room_code); $$;
create or replace function public.submit_hit(p_room_code text, p_game_id uuid, p_round_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.submit_hit(p_room_code, p_game_id, p_round_id); $$;

revoke all on function private.game_snapshot(text) from public, anon;
revoke all on function private.advance_game(text) from public, anon;
revoke all on function private.submit_hit(text, uuid, uuid) from public, anon;
revoke all on function public.game_snapshot(text) from public, anon;
revoke all on function public.advance_game(text) from public, anon;
revoke all on function public.submit_hit(text, uuid, uuid) from public, anon;
grant execute on function public.game_snapshot(text) to authenticated;
grant execute on function public.advance_game(text) to authenticated;
grant execute on function public.submit_hit(text, uuid, uuid) to authenticated;

do $$
begin
  if not exists (select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rounds') then
    alter publication supabase_realtime add table public.rounds;
  end if;
  if not exists (select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_scores') then
    alter publication supabase_realtime add table public.game_scores;
  end if;
end;
$$;
