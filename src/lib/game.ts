import { ensureAnonymousSession, supabase } from './supabase'

export type GamePlayer = { id: string; display_name: string; is_host: boolean }
export type GameRound = {
  id: string
  round_number: number
  status: 'pending' | 'target_ready' | 'resolved' | 'expired'
  scheduled_at: string | null
  opened_at: string | null
  closes_at: string | null
  target_x: number | null
  target_y: number | null
  winner_player_id: string | null
}
export type GameSnapshot = {
  server_now: string
  room: { id: string; code: string; host_player_id: string }
  current_player_id: string
  game: {
    id: string
    game_number: number
    status: 'countdown' | 'active' | 'completed' | 'cancelled'
    started_at: string | null
    countdown_ends_at: string | null
    completed_at: string | null
    current_round_number: number
  }
  players: GamePlayer[]
  round: GameRound | null
  round_history: { round_number: number; status: 'resolved' | 'expired'; winner_player_id: string | null; winner_name: string | null }[]
  leaderboard: { player_id: string; display_name: string; score: number }[]
}

function getClient() {
  if (!supabase) throw new Error('Supabase is not configured. Set VITE_SUPABASE_URL and the public key in .env.local.')
  return supabase
}

function parseRpcError(error: { message: string }): never {
  const code = error.message.match(/(?:STALE_TARGET|NOT_A_ROOM_MEMBER|ROOM_NOT_FOUND|HOST_ONLY|NEED_MORE_PLAYERS|GAME_ALREADY_STARTED|AUTHENTICATION_REQUIRED)/)?.[0]
  const messages: Record<string, string> = {
    STALE_TARGET: 'That target is no longer active. The next round is coming up.',
    NOT_A_ROOM_MEMBER: 'Your player session is no longer in this room. Rejoin the room to continue.',
    ROOM_NOT_FOUND: 'This room has expired or no longer exists.',
    HOST_ONLY: 'Only the host can start or replay this game.',
    NEED_MORE_PLAYERS: 'At least two players are required to play.',
    GAME_ALREADY_STARTED: 'A game is already in progress.',
    AUTHENTICATION_REQUIRED: 'Your player session expired. Refresh and reconnect.',
  }
  throw new Error(code ? messages[code] : error.message)
}

async function callSnapshot(name: 'game_snapshot' | 'advance_game', params: Record<string, string>) {
  const client = getClient()
  await ensureAnonymousSession()
  const { data, error } = await client.rpc(name, params)
  if (error) parseRpcError(error)
  return data as unknown as GameSnapshot
}

export function getGameSnapshot(roomCode: string) {
  return callSnapshot('game_snapshot', { p_room_code: roomCode.trim().toUpperCase() })
}

export function advanceGame(roomCode: string) {
  return callSnapshot('advance_game', { p_room_code: roomCode.trim().toUpperCase() })
}

export async function submitHit(roomCode: string, gameId: string, roundId: string) {
  const client = getClient()
  await ensureAnonymousSession()
  const { data, error } = await client.rpc('submit_hit', {
    p_room_code: roomCode.trim().toUpperCase(),
    p_game_id: gameId,
    p_round_id: roundId,
  })
  if (error) parseRpcError(error)
  return data as unknown as GameSnapshot
}

export function subscribeToGame(roomId: string, onChange: () => void, onStatus: (status: string) => void) {
  const client = getClient()
  const channel = client.channel(`game:${roomId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'games', filter: `room_id=eq.${roomId}` }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'game_scores', filter: `room_id=eq.${roomId}` }, onChange)
    .subscribe(onStatus)
  return () => { void client.removeChannel(channel) }
}
