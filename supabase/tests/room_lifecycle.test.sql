begin;
select plan(20);

select has_table('public', 'rooms', 'rooms table exists');
select has_table('public', 'players', 'players table exists');
select has_table('public', 'games', 'games table exists');
select has_table('public', 'rounds', 'rounds table exists');

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, is_anonymous)
select ('00000000-0000-0000-0000-' || pg_catalog.lpad(n::text, 12, '0'))::uuid,
       'authenticated', 'authenticated', 'neon-test-' || n::text || '@example.invalid',
       '{}'::jsonb, '{}'::jsonb, true
  from pg_catalog.generate_series(1, 9) as n;

create temporary table test_snapshots (label text primary key, snapshot jsonb not null);
grant select, insert on test_snapshots to authenticated;

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":true}', true);
set local role authenticated;

insert into pg_temp.test_snapshots(label, snapshot)
select 'created', public.create_room('Host');
select ok((select snapshot #>> '{room,status}' = 'waiting' from pg_temp.test_snapshots where label = 'created'), 'room creation returns a waiting room');
select is((select jsonb_array_length(snapshot->'players') from pg_temp.test_snapshots where label = 'created'), 1, 'creator is the first player');
select is((select snapshot #>> '{players,0,is_host}' from pg_temp.test_snapshots where label = 'created'), 'true', 'creator is the host');
select throws_ok(
  'select public.start_game(''' || (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created') || ''')',
  'P0001', 'NEED_MORE_PLAYERS', 'host cannot start with fewer than two players'
);

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":true}', true);
insert into pg_temp.test_snapshots(label, snapshot)
select 'joined', public.join_room('Guest', snapshot #>> '{room,code}')
  from pg_temp.test_snapshots where label = 'created';
select is((select jsonb_array_length(snapshot->'players') from pg_temp.test_snapshots where label = 'joined'), 2, 'join adds a second player');
select throws_ok(
  'select public.start_game(''' || (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created') || ''')',
  'P0001', 'HOST_ONLY', 'non-host cannot start the game'
);
select ok(not has_table_privilege('authenticated', 'public.players', 'UPDATE'), 'clients cannot write player rows directly');
select ok(not has_table_privilege('authenticated', 'private.player_sessions', 'SELECT'), 'persistent session identities are private');

do $capacity_check$
declare
  i integer;
  v_user_id text;
  v_room_code text := (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created');
begin
  for i in 3..8 loop
    v_user_id := '00000000-0000-0000-0000-' || pg_catalog.lpad(i::text, 12, '0');
    perform pg_catalog.set_config('request.jwt.claim.sub', v_user_id, true);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_user_id, 'role', 'authenticated', 'is_anonymous', true)::text, true);
    perform public.join_room('Player ' || i::text, v_room_code);
  end loop;
end;
$capacity_check$;

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":true}', true);
insert into pg_temp.test_snapshots(label, snapshot)
select 'full', public.get_lobby_snapshot(snapshot #>> '{room,code}')
  from pg_temp.test_snapshots where label = 'created';
select is((select jsonb_array_length(snapshot->'players') from pg_temp.test_snapshots where label = 'full'), 8, 'lobby stops at eight active players');

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000009","role":"authenticated","is_anonymous":true}', true);
select throws_ok(
  'select public.join_room(''Ninth'', ''' || (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created') || ''')',
  'P0001', 'ROOM_FULL', 'a ninth player cannot join the full room'
);

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":true}', true);
insert into pg_temp.test_snapshots(label, snapshot)
select 'started', public.start_game(snapshot #>> '{room,code}')
  from pg_temp.test_snapshots where label = 'created';
select is((select snapshot #>> '{room,status}' from pg_temp.test_snapshots where label = 'started'), 'started', 'host starts the room atomically');
select is((select snapshot #>> '{game,status}' from pg_temp.test_snapshots where label = 'started'), 'ready', 'start creates a real game row without beginning gameplay');
select is((select pg_catalog.count(*) from public.rounds as round where round.room_id = (select (snapshot #>> '{room,id}')::uuid from pg_temp.test_snapshots where label = 'started')), 0::bigint, 'starting the room does not create simulated rounds');
select throws_ok(
  'select public.start_game(''' || (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created') || ''')',
  'P0001', 'GAME_ALREADY_STARTED', 'a second start cannot create another unfinished game'
);
select lives_ok(
  'select public.leave_room(''' || (select snapshot #>> '{room,code}' from pg_temp.test_snapshots where label = 'created') || ''')',
  'host can leave through the room RPC'
);

select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select pg_catalog.set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":true}', true);
insert into pg_temp.test_snapshots(label, snapshot)
select 'migrated', public.get_lobby_snapshot(snapshot #>> '{room,code}')
  from pg_temp.test_snapshots where label = 'created';
select is(
  (select snapshot #>> '{room,host_player_id}' from pg_temp.test_snapshots where label = 'migrated'),
  (select snapshot #>> '{players,1,id}' from pg_temp.test_snapshots where label = 'joined'),
  'host role migrates to a remaining player'
);

select * from finish();
rollback;
