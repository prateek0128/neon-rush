create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[0-9A-F]{8}$'),
  host_player_id uuid,
  status text not null default 'waiting' check (status in ('waiting', 'started', 'expired')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (expires_at > created_at)
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  display_name text not null check (
    char_length(btrim(display_name)) between 1 and 18
    and display_name !~ '[[:cntrl:]]'
  ),
  joined_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  left_at timestamptz,
  unique (id, room_id)
);

create table if not exists private.player_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  player_id uuid not null unique references public.players(id) on delete cascade,
  linked_at timestamptz not null default clock_timestamp()
);
revoke all on table private.player_sessions from public, anon, authenticated;

alter table public.rooms
  add constraint rooms_host_player_fk
  foreign key (host_player_id) references public.players(id) on delete set null;

create index if not exists players_active_by_room
  on public.players(room_id, joined_at) where left_at is null;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  game_number integer not null check (game_number > 0),
  status text not null default 'ready' check (status in ('ready', 'countdown', 'active', 'completed', 'cancelled')),
  started_by_player_id uuid not null references public.players(id),
  created_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  unique (room_id, game_number),
  unique (id, room_id),
  check ((status <> 'completed') or completed_at is not null)
);

create unique index if not exists games_one_unfinished_game_per_room
  on public.games(room_id) where status not in ('completed', 'cancelled');

create table if not exists public.rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  game_id uuid not null,
  round_number integer not null check (round_number between 1 and 10),
  status text not null default 'pending' check (status in ('pending', 'target_ready', 'resolved', 'expired')),
  opened_at timestamptz,
  closes_at timestamptz,
  resolved_at timestamptz,
  winner_player_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  foreign key (game_id, room_id) references public.games(id, room_id) on delete cascade,
  foreign key (winner_player_id, room_id) references public.players(id, room_id),
  unique (game_id, round_number),
  check ((status <> 'resolved') or resolved_at is not null),
  check (closes_at is null or opened_at is null or closes_at > opened_at)
);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.games enable row level security;
alter table public.rounds enable row level security;

create or replace function private.current_player_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.jwt() ->> 'is_anonymous') = 'true' then (select auth.uid())
    else null::uuid
  end;
$$;
revoke all on function private.current_player_user_id() from public, anon, authenticated;

create or replace function private.is_room_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
    where player.room_id = p_room_id
      and player_session.user_id = (select private.current_player_user_id())
      and player.left_at is null
  );
$$;

revoke all on function private.is_room_member(uuid) from public, anon;
grant execute on function private.is_room_member(uuid) to authenticated;

create policy room_members_can_read_rooms
  on public.rooms for select to authenticated
  using (private.is_room_member(id));
create policy room_members_can_read_players
  on public.players for select to authenticated
  using (private.is_room_member(room_id));
create policy room_members_can_read_games
  on public.games for select to authenticated
  using (private.is_room_member(room_id));
create policy room_members_can_read_rounds
  on public.rounds for select to authenticated
  using (private.is_room_member(room_id));

revoke all on public.rooms, public.players, public.games, public.rounds from public, anon, authenticated;
grant select on public.rooms, public.players, public.games, public.rounds to authenticated;

create or replace function private.prune_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.players as player
     set left_at = clock_timestamp()
   where player.room_id = p_room_id
     and player.left_at is null
     and not exists (
       select 1 from private.player_sessions as player_session
        where player_session.player_id = player.id
          and player_session.user_id = (select private.current_player_user_id())
     )
     and player.last_seen_at < clock_timestamp() - interval '75 seconds';

  update public.rooms as room
     set host_player_id = (
       select player.id
         from public.players as player
        where player.room_id = p_room_id
          and player.left_at is null
        order by player.joined_at, player.id
        limit 1
     )
   where room.id = p_room_id
     and not exists (
       select 1 from public.players as host
        where host.id = room.host_player_id
          and host.room_id = p_room_id
          and host.left_at is null
     );
end;
$$;

create or replace function private.make_lobby_snapshot(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'room', jsonb_build_object(
      'id', room.id,
      'code', room.code,
      'status', room.status,
      'host_player_id', room.host_player_id,
      'expires_at', room.expires_at
    ),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', player.id,
        'display_name', player.display_name,
        'is_host', player.id = room.host_player_id,
        'is_online', player.last_seen_at >= now() - interval '75 seconds',
        'joined_at', player.joined_at
      ) order by player.joined_at, player.id)
      from public.players as player
      where player.room_id = room.id and player.left_at is null
    ), '[]'::jsonb),
    'current_player_id', (
      select player.id from private.player_sessions as player_session
       join public.players as player on player.id = player_session.player_id
       where player.room_id = room.id
         and player_session.user_id = (select private.current_player_user_id())
         and player.left_at is null
       limit 1
    ),
    'game', (
      select jsonb_build_object('id', game.id, 'game_number', game.game_number, 'status', game.status)
        from public.games as game
       where game.room_id = room.id
       order by game.game_number desc
       limit 1
    )
  )
  from public.rooms as room
  where room.id = p_room_id;
$$;

create or replace function private.validate_display_name(p_display_name text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_name text := pg_catalog.btrim(p_display_name);
begin
  if v_name is null or pg_catalog.char_length(v_name) not between 1 and 18 or v_name ~ '[[:cntrl:]]' then
    raise exception using errcode = 'P0001', message = 'DISPLAY_NAME_INVALID';
  end if;
  return v_name;
end;
$$;

create or replace function private.create_room(p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room_id uuid := gen_random_uuid();
  v_player_id uuid := gen_random_uuid();
  v_code text;
  v_attempt integer := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));

  if exists (
    select 1 from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
    where player_session.user_id = v_user_id and player.left_at is null
  ) then
    raise exception using errcode = 'P0001', message = 'ALREADY_IN_OTHER_ROOM';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := pg_catalog.upper(pg_catalog.substr(pg_catalog.replace(gen_random_uuid()::text, '-', ''), 1, 8));
    begin
      insert into public.rooms(id, code, status, expires_at)
      values (v_room_id, v_code, 'waiting', clock_timestamp() + interval '12 hours');
      exit;
    exception when unique_violation then
      if v_attempt >= 5 then
        raise exception using errcode = 'P0001', message = 'ROOM_CODE_GENERATION_FAILED';
      end if;
    end;
  end loop;

  insert into public.players(id, room_id, display_name)
  values (v_player_id, v_room_id, private.validate_display_name(p_display_name));
  insert into private.player_sessions(user_id, player_id)
  values (v_user_id, v_player_id)
  on conflict (user_id) do update
    set player_id = excluded.player_id, linked_at = clock_timestamp();
  update public.rooms set host_player_id = v_player_id where id = v_room_id;
  return private.make_lobby_snapshot(v_room_id);
end;
$$;

create or replace function private.join_room(p_display_name text, p_room_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_player public.players%rowtype;
  v_display_name text := private.validate_display_name(p_display_name);
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  if p_room_code is null or pg_catalog.upper(pg_catalog.btrim(p_room_code)) !~ '^[A-F0-9]{8}$' then
    raise exception using errcode = 'P0001', message = 'ROOM_CODE_INVALID';
  end if;

  select * into v_room from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code))
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'expired' or (v_room.status = 'waiting' and v_room.expires_at <= clock_timestamp()) then
    raise exception using errcode = 'P0001', message = 'ROOM_EXPIRED';
  end if;
  if v_room.status <> 'waiting' then raise exception using errcode = 'P0001', message = 'ROOM_NOT_JOINABLE'; end if;

  perform private.prune_room(v_room.id);
  select player.* into v_player
    from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
   where player_session.user_id = v_user_id and player.left_at is null
   limit 1;
  if found and v_player.room_id <> v_room.id then
    raise exception using errcode = 'P0001', message = 'ALREADY_IN_OTHER_ROOM';
  end if;

  if not found then
    select player.* into v_player
      from private.player_sessions as player_session
      join public.players as player on player.id = player_session.player_id
     where player_session.user_id = v_user_id and player.room_id = v_room.id
     order by player.joined_at desc limit 1
     for update;
    if found then
      if (select count(*) from public.players where room_id = v_room.id and left_at is null) >= 8 then
        raise exception using errcode = 'P0001', message = 'ROOM_FULL';
      end if;
      update public.players
         set left_at = null, last_seen_at = clock_timestamp(), display_name = v_display_name
       where id = v_player.id
       returning * into v_player;
    else
      if (select count(*) from public.players where room_id = v_room.id and left_at is null) >= 8 then
        raise exception using errcode = 'P0001', message = 'ROOM_FULL';
      end if;
      insert into public.players(room_id, display_name)
      values (v_room.id, v_display_name)
      returning * into v_player;
    end if;
  else
    update public.players set last_seen_at = clock_timestamp(), display_name = v_display_name
     where id = v_player.id returning * into v_player;
  end if;

  insert into private.player_sessions(user_id, player_id)
  values (v_user_id, v_player.id)
  on conflict (user_id) do update
    set player_id = excluded.player_id, linked_at = clock_timestamp();

  perform private.prune_room(v_room.id);
  return private.make_lobby_snapshot(v_room.id);
end;
$$;

create or replace function private.get_lobby_snapshot(p_room_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room public.rooms%rowtype;
  v_player public.players%rowtype;
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  select * into v_room from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code))
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'expired' or (v_room.status = 'waiting' and v_room.expires_at <= clock_timestamp()) then
    raise exception using errcode = 'P0001', message = 'ROOM_EXPIRED';
  end if;

  if exists (
    select 1 from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
    where player_session.user_id = v_user_id and player.left_at is null and player.room_id <> v_room.id
  ) then
    raise exception using errcode = 'P0001', message = 'ALREADY_IN_OTHER_ROOM';
  end if;

  select player.* into v_player
    from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
   where player_session.user_id = v_user_id and player.room_id = v_room.id
   order by (player.left_at is null) desc, player.joined_at desc limit 1
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;

  perform private.prune_room(v_room.id);
  if v_player.left_at is not null and (select count(*) from public.players where room_id = v_room.id and left_at is null) >= 8 then
    raise exception using errcode = 'P0001', message = 'ROOM_FULL';
  end if;
  update public.players
     set left_at = null, last_seen_at = clock_timestamp()
   where id = v_player.id
     and (left_at is not null or last_seen_at < clock_timestamp() - interval '20 seconds')
   returning * into v_player;
  return private.make_lobby_snapshot(v_room.id);
end;
$$;

create or replace function private.lobby_heartbeat(p_room_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select private.current_player_user_id());
  v_room_id uuid;
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  select id into v_room_id from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code))
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  update public.players
     set last_seen_at = clock_timestamp()
   where room_id = v_room_id
     and id = (select player_session.player_id from private.player_sessions as player_session where player_session.user_id = v_user_id)
     and left_at is null;
  if not found then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  perform private.prune_room(v_room_id);
end;
$$;

create or replace function private.leave_room(p_room_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_id uuid;
  v_user_id uuid := (select private.current_player_user_id());
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  select id into v_room_id from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code))
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  update public.players set left_at = clock_timestamp()
   where room_id = v_room_id
     and id = (select player_session.player_id from private.player_sessions as player_session where player_session.user_id = v_user_id)
     and left_at is null;
  if not found then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  perform private.prune_room(v_room_id);
  if not exists (select 1 from public.players where room_id = v_room_id and left_at is null) then
    update public.rooms set status = 'expired' where id = v_room_id and status = 'waiting';
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
  v_player_id uuid;
  v_count integer;
  v_game_number integer;
begin
  if v_user_id is null then raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  select * into v_room from public.rooms
   where code = pg_catalog.upper(pg_catalog.btrim(p_room_code))
   for update;
  if not found then raise exception using errcode = 'P0001', message = 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'expired' or v_room.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'ROOM_EXPIRED';
  end if;
  if v_room.status <> 'waiting' then raise exception using errcode = 'P0001', message = 'GAME_ALREADY_STARTED'; end if;

  perform private.prune_room(v_room.id);
  select player.id into v_player_id
    from private.player_sessions as player_session
    join public.players as player on player.id = player_session.player_id
   where player.room_id = v_room.id and player_session.user_id = v_user_id and player.left_at is null;
  if v_player_id is null then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  if v_player_id <> v_room.host_player_id then raise exception using errcode = 'P0001', message = 'HOST_ONLY'; end if;

  select count(*)::integer into v_count from public.players where room_id = v_room.id and left_at is null;
  if v_count < 2 then raise exception using errcode = 'P0001', message = 'NEED_MORE_PLAYERS'; end if;
  select coalesce(max(game_number), 0) + 1 into v_game_number from public.games where room_id = v_room.id;
  insert into public.games(room_id, game_number, status, started_by_player_id, started_at)
  values (v_room.id, v_game_number, 'ready', v_player_id, clock_timestamp());
  update public.rooms set status = 'started' where id = v_room.id;
  return private.make_lobby_snapshot(v_room.id);
end;
$$;

revoke all on function private.prune_room(uuid) from public, anon;
revoke all on function private.make_lobby_snapshot(uuid) from public, anon;
revoke all on function private.validate_display_name(text) from public, anon;
revoke all on function private.create_room(text) from public, anon;
revoke all on function private.join_room(text, text) from public, anon;
revoke all on function private.get_lobby_snapshot(text) from public, anon;
revoke all on function private.lobby_heartbeat(text) from public, anon;
revoke all on function private.leave_room(text) from public, anon;
revoke all on function private.start_game(text) from public, anon;
grant execute on function private.create_room(text) to authenticated;
grant execute on function private.join_room(text, text) to authenticated;
grant execute on function private.get_lobby_snapshot(text) to authenticated;
grant execute on function private.lobby_heartbeat(text) to authenticated;
grant execute on function private.leave_room(text) to authenticated;
grant execute on function private.start_game(text) to authenticated;

create or replace function public.create_room(p_display_name text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.create_room(p_display_name); $$;
create or replace function public.join_room(p_display_name text, p_room_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.join_room(p_display_name, p_room_code); $$;
create or replace function public.get_lobby_snapshot(p_room_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.get_lobby_snapshot(p_room_code); $$;
create or replace function public.lobby_heartbeat(p_room_code text)
returns void language sql security invoker set search_path = ''
as $$ select private.lobby_heartbeat(p_room_code); $$;
create or replace function public.leave_room(p_room_code text)
returns void language sql security invoker set search_path = ''
as $$ select private.leave_room(p_room_code); $$;
create or replace function public.start_game(p_room_code text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.start_game(p_room_code); $$;

revoke all on function public.create_room(text) from public, anon;
revoke all on function public.join_room(text, text) from public, anon;
revoke all on function public.get_lobby_snapshot(text) from public, anon;
revoke all on function public.lobby_heartbeat(text) from public, anon;
revoke all on function public.leave_room(text) from public, anon;
revoke all on function public.start_game(text) from public, anon;
grant execute on function public.create_room(text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;
grant execute on function public.get_lobby_snapshot(text) to authenticated;
grant execute on function public.lobby_heartbeat(text) to authenticated;
grant execute on function public.leave_room(text) to authenticated;
grant execute on function public.start_game(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms') then
    alter publication supabase_realtime add table public.rooms;
  end if;
  if not exists (select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players') then
    alter publication supabase_realtime add table public.players;
  end if;
  if not exists (select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'games') then
    alter publication supabase_realtime add table public.games;
  end if;
end;
$$;
