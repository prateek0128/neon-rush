import { ensureAnonymousSession, supabase } from './supabase'

export type LobbyPlayer = {
  id: string
  display_name: string
  is_host: boolean
  is_online: boolean
  joined_at: string
}

export type LobbySnapshot = {
  room: {
    id: string
    code: string
    status: 'waiting' | 'started' | 'expired'
    host_player_id: string | null
    expires_at: string
  }
  players: LobbyPlayer[]
  current_player_id: string
  game: { id: string; game_number: number; status: 'ready' } | null
}

function getClient() {
  if (!supabase) throw new Error('Supabase is not configured. Add your Supabase URL and public key to .env.local, then restart Vite.')
  return supabase
}

function throwRpcError(error: { message: string }): never {
  const message = error.message
  const code = message.match(/(?:ROOM_NOT_FOUND|ROOM_EXPIRED|ROOM_NOT_JOINABLE|ROOM_FULL|DISPLAY_NAME_INVALID|ALREADY_IN_OTHER_ROOM|NOT_A_ROOM_MEMBER|HOST_ONLY|NEED_MORE_PLAYERS|GAME_ALREADY_STARTED|ROOM_CODE_INVALID)/)?.[0]
  const messages: Record<string, string> = {
    ROOM_NOT_FOUND: 'That room code was not found. Check the code and try again.',
    ROOM_EXPIRED: 'That room has expired. Ask the host to create a new room.',
    ROOM_NOT_JOINABLE: 'That game has already started and is no longer accepting players.',
    ROOM_FULL: 'This room is full. Neon Rush rooms support up to 8 players.',
    DISPLAY_NAME_INVALID: 'Enter a display name between 1 and 18 characters.',
    ALREADY_IN_OTHER_ROOM: 'Your player session is already in another room. Leave it before joining a new one.',
    NOT_A_ROOM_MEMBER: 'This browser session is not a player in that room. Join it from the Join Room page.',
    HOST_ONLY: 'Only the room host can start the game.',
    NEED_MORE_PLAYERS: 'At least 2 players must be in the room before the host can start.',
    GAME_ALREADY_STARTED: 'This room has already started a game.',
    ROOM_CODE_INVALID: 'Room codes use 8 characters: A–F and 0–9.',
  }
  throw new Error(code ? messages[code] : message)
}

async function rpcSnapshot(name: 'create_room' | 'join_room' | 'get_lobby_snapshot' | 'start_game', params: Record<string, string>) {
  const client = getClient()
  await ensureAnonymousSession()
  const { data, error } = await client.rpc(name, params)
  if (error) throwRpcError(error)
  return data as unknown as LobbySnapshot
}

export async function createRoom(displayName: string) {
  return rpcSnapshot('create_room', { p_display_name: displayName.trim() })
}

export async function joinRoom(displayName: string, roomCode: string) {
  return rpcSnapshot('join_room', { p_display_name: displayName.trim(), p_room_code: roomCode.trim().toUpperCase() })
}

export async function getLobbySnapshot(roomCode: string) {
  return rpcSnapshot('get_lobby_snapshot', { p_room_code: roomCode.trim().toUpperCase() })
}

export async function startGame(roomCode: string) {
  return rpcSnapshot('start_game', { p_room_code: roomCode.trim().toUpperCase() })
}

export async function sendLobbyHeartbeat(roomCode: string) {
  const client = getClient()
  await ensureAnonymousSession()
  const { error } = await client.rpc('lobby_heartbeat', { p_room_code: roomCode.trim().toUpperCase() })
  if (error) throwRpcError(error)
}

export async function leaveRoom(roomCode: string) {
  const client = getClient()
  await ensureAnonymousSession()
  const { error } = await client.rpc('leave_room', { p_room_code: roomCode.trim().toUpperCase() })
  if (error) throwRpcError(error)
}

export function subscribeToLobby(roomId: string, onChange: () => void, onStatus: (status: string) => void) {
  const client = getClient()
  const channel = client.channel(`lobby:${roomId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'games', filter: `room_id=eq.${roomId}` }, onChange)
    .subscribe(onStatus)
  return () => { void client.removeChannel(channel) }
}
