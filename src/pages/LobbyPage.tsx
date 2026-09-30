import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Button } from '../components/Button'
import { PageTransition } from '../components/PageTransition'
import { getLobbySnapshot, leaveRoom, sendLobbyHeartbeat, startGame, subscribeToLobby, type LobbySnapshot } from '../lib/rooms'

function friendlyError(cause: unknown) {
  return cause instanceof Error ? cause.message : 'Unable to load this room. Please try again.'
}

export function LobbyPage() {
  const { roomCode = '' } = useParams()
  const navigate = useNavigate()
  const [snapshot, setSnapshot] = useState<LobbySnapshot | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [starting, setStarting] = useState(false)
  const [leaving, setLeaving] = useState(false)
  const [copied, setCopied] = useState(false)
  const [connection, setConnection] = useState('CONNECTING')

  useEffect(() => {
    if (snapshot?.room.status === 'started') navigate(`/room/${roomCode}/game`, { replace: true })
  }, [snapshot?.room.status, navigate, roomCode])

  const refresh = useCallback(async (heartbeat = false) => {
    if (heartbeat) await sendLobbyHeartbeat(roomCode)
    const next = await getLobbySnapshot(roomCode)
    setSnapshot(next)
    setError('')
    return next
  }, [roomCode])

  useEffect(() => {
    let cancelled = false
    let stopSubscription: (() => void) | undefined
    let subscribedRoomId = ''

    const load = async (heartbeat = false) => {
      try {
        const next = await refresh(heartbeat)
        if (cancelled) return
        if (subscribedRoomId !== next.room.id) {
          stopSubscription?.()
          subscribedRoomId = next.room.id
          stopSubscription = subscribeToLobby(next.room.id, () => { void load() }, setConnection)
        }
      } catch (cause) {
        if (!cancelled) setError(friendlyError(cause))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void load()
    const heartbeatTimer = window.setInterval(() => { void load(true) }, 25_000)
    return () => {
      cancelled = true
      window.clearInterval(heartbeatTimer)
      stopSubscription?.()
    }
  }, [refresh])

  async function handleStart() {
    setStarting(true)
    setError('')
    try {
      setSnapshot(await startGame(roomCode))
      navigate(`/room/${roomCode}/game`)
    } catch (cause) {
      setError(friendlyError(cause))
    } finally {
      setStarting(false)
    }
  }

  async function handleLeave() {
    setLeaving(true)
    setError('')
    try {
      await leaveRoom(roomCode)
      navigate('/')
    } catch (cause) {
      setError(friendlyError(cause))
      setLeaving(false)
    }
  }

  async function copyRoomCode() {
    if (!snapshot) return
    try {
      await navigator.clipboard.writeText(snapshot.room.code)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      setError('Copy is unavailable in this browser. Share the room code shown above.')
    }
  }

  if (loading) return <PageTransition className="lobby-page"><div className="lobby-state-card"><span className="lobby-kicker">NEON RUSH / CONNECTION</span><h1>ENTERING<br /><span>THE ARENA.</span></h1><p>Reconnecting your player session…</p></div></PageTransition>

  if (!snapshot) return <PageTransition className="lobby-page"><div className="lobby-state-card"><span className="lobby-kicker">ROOM / {roomCode || 'UNKNOWN'}</span><h1>CAN’T FIND<br /><span>THE ROOM.</span></h1><p role="alert" className="lobby-error">{error}</p><div className="lobby-state-actions"><Button to="/join" variant="secondary">Join another room</Button><Button to="/">Back home</Button></div></div></PageTransition>

  const isHost = snapshot.current_player_id === snapshot.room.host_player_id
  const canStart = isHost && snapshot.room.status === 'waiting' && snapshot.players.length >= 2 && !starting

  return <PageTransition className="lobby-page">
    <Link className="back-link" to="/">← <span>Leave the arena</span></Link>
    <section className="lobby-shell">
      <div className="lobby-heading">
        <div>
          <div className="eyebrow"><span className="eyebrow-line" /> REAL-TIME MULTIPLAYER LOBBY</div>
          <h1>YOUR CREW.<br /><span>YOUR ARENA.</span></h1>
          <p>Waiting for the fastest hands in the room.</p>
        </div>
        <div className={`connection-pill ${connection === 'SUBSCRIBED' ? 'connection-online' : ''}`}><span /> {connection === 'SUBSCRIBED' ? 'LIVE CONNECTION' : connection}</div>
      </div>

      <div className="lobby-grid">
        <div className="lobby-roster-card">
          <div className="lobby-card-top"><span>PLAYERS IN THE ROOM</span><span className="player-count">{snapshot.players.length}<i> / 8</i></span></div>
          <div className="player-roster" aria-live="polite">
            {snapshot.players.map((player, index) => <div className="player-row" key={player.id}>
              <span className={`player-index${index === 0 ? ' player-index-first' : ''}`}>{String(index + 1).padStart(2, '0')}</span>
              <span className="player-avatar">{player.display_name.slice(0, 1).toUpperCase()}</span>
              <span className="player-name">{player.display_name}{player.id === snapshot.current_player_id && <small>YOU</small>}</span>
              {player.is_host && <span className="host-badge">HOST <b>✦</b></span>}
              <span className={`player-presence${player.is_online ? ' is-online' : ''}`} title={player.is_online ? 'Online' : 'Reconnecting'} />
            </div>)}
            {Array.from({ length: Math.max(0, 8 - snapshot.players.length) }, (_, index) => <div className="player-row player-row-open" key={`open-${index}`}>
              <span className="player-index">{String(snapshot.players.length + index + 1).padStart(2, '0')}</span><span className="player-avatar player-avatar-empty">+</span><span className="player-name">Waiting for player</span><span className="open-slot">OPEN SLOT</span>
            </div>)}
          </div>
          <div className="roster-foot"><span className="live-dot" /> Players appear here as they join</div>
        </div>

        <aside className="lobby-side-column">
          <div className="room-code-card">
            <span className="room-code-kicker">SHARE THIS ROOM CODE</span>
            <button className="room-code-value" type="button" onClick={() => void copyRoomCode()} aria-label="Copy room code">{snapshot.room.code}<span>{copied ? 'COPIED' : 'COPY ↗'}</span></button>
            <p>Share this code with friends to join your lobby.</p>
          </div>
          <div className="lobby-action-card">
            <div className="lobby-action-icon">{snapshot.room.status === 'started' ? '✦' : '↯'}</div>
            <h2>{snapshot.room.status === 'started' ? 'Arena locked in.' : isHost ? 'Ready when you are.' : 'The host is in control.'}</h2>
            <p>{snapshot.room.status === 'started'
              ? 'Your game is ready. Returning players will reconnect to the shared match.'
              : isHost
                ? snapshot.players.length < 2 ? 'Invite at least one more player to unlock the start.' : 'All players are in. Start the game when your crew is ready.'
                : 'The host will start the game once everyone is ready.'}</p>
            {snapshot.room.status === 'waiting' && isHost && <Button fullWidth disabled={!canStart} onClick={() => void handleStart()}>{starting ? 'Starting…' : 'Start game'} <span className="button-arrow">↗</span></Button>}
            {snapshot.room.status === 'waiting' && !isHost && <div className="waiting-host"><span className="waiting-pulse" /> WAITING FOR HOST</div>}
            {snapshot.room.status === 'started' && <div className="waiting-host"><span className="waiting-pulse" /> MULTIPLAYER LOBBY ACTIVE</div>}
          </div>
        </aside>
      </div>
      {error && <p className="lobby-error lobby-action-error" role="alert">{error}</p>}
      <div className="lobby-bottomline"><span>2–8 PLAYERS</span><span>ROOM EXPIRES {new Date(snapshot.room.expires_at).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}</span><button type="button" onClick={() => void handleLeave()} disabled={leaving}>{leaving ? 'LEAVING…' : 'LEAVE ROOM'}</button></div>
    </section>
  </PageTransition>
}
