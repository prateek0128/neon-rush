alter table public.game_scores
  drop constraint game_scores_player_id_room_id_fkey,
  add constraint game_scores_player_id_room_id_fkey
    foreign key (player_id, room_id) references public.players(id, room_id) on delete cascade;
