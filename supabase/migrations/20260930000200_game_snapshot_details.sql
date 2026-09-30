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
    select 1 from private.player_sessions ps join public.players p on p.id = ps.player_id
     where ps.user_id = v_user_id and p.room_id = v_room.id and p.left_at is null
  ) then raise exception using errcode = 'P0001', message = 'NOT_A_ROOM_MEMBER'; end if;
  perform private.advance_game(p_room_code);
  select * into v_game from public.games where room_id = v_room.id order by game_number desc limit 1;
  if not found then raise exception using errcode = 'P0001', message = 'GAME_NOT_STARTED'; end if;

  return jsonb_build_object(
    'server_now', clock_timestamp(),
    'room', jsonb_build_object('id', v_room.id, 'code', v_room.code, 'host_player_id', v_room.host_player_id),
    'current_player_id', (select ps.player_id from private.player_sessions ps where ps.user_id = v_user_id),
    'game', jsonb_build_object('id', v_game.id, 'game_number', v_game.game_number, 'status', v_game.status,
      'started_at', v_game.started_at, 'countdown_ends_at', v_game.countdown_ends_at,
      'completed_at', v_game.completed_at, 'current_round_number', v_game.current_round_number),
    'players', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'display_name', p.display_name, 'is_host', p.id = v_room.host_player_id
    ) order by p.joined_at, p.id) from public.players p
      where p.room_id = v_room.id and p.left_at is null), '[]'::jsonb),
    'round', (select jsonb_build_object('id', r.id, 'round_number', r.round_number, 'status', r.status,
      'scheduled_at', r.scheduled_at, 'opened_at', r.opened_at, 'closes_at', r.closes_at,
      'target_x', r.target_x, 'target_y', r.target_y, 'winner_player_id', r.winner_player_id)
      from public.rounds r where r.game_id = v_game.id and r.round_number = v_game.current_round_number),
    'round_history', coalesce((select jsonb_agg(jsonb_build_object(
      'round_number', r.round_number, 'status', r.status, 'winner_player_id', r.winner_player_id,
      'winner_name', winner.display_name
    ) order by r.round_number) from public.rounds r
      left join public.players winner on winner.id = r.winner_player_id
      where r.game_id = v_game.id and r.status in ('resolved', 'expired')), '[]'::jsonb),
    'leaderboard', coalesce((select jsonb_agg(jsonb_build_object(
      'player_id', gs.player_id, 'display_name', p.display_name, 'score', gs.score
    ) order by gs.score desc, p.joined_at, p.id)
      from public.game_scores gs join public.players p on p.id = gs.player_id
      where gs.game_id = v_game.id), '[]'::jsonb)
  );
end;
$$;
