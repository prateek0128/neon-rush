import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Button } from '../components/Button'
import { PageTransition } from '../components/PageTransition'
import { advanceGame, getGameSnapshot, submitHit, subscribeToGame, type GameSnapshot } from '../lib/game'
import { getLobbySnapshot, leaveRoom, sendLobbyHeartbeat, startGame } from '../lib/rooms'

function friendlyError(cause: unknown) {
  return cause instanceof Error ? cause.message : 'The game connection was interrupted. Reconnecting…'
}

export function GamePage() {
  const { roomCode = '' } = useParams()
  const navigate = useNavigate()
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null)
  const [error, setError] = useState('')
  const [connection, setConnection] = useState('CONNECTING')
  const [now, setNow] = useState(Date.now())
  const [hitting, setHitting] = useState(false)
  const [replaying, setReplaying] = useState(false)
  const [leaving, setLeaving] = useState(false)
  const [feedback, setFeedback] = useState('')
  const busy = useRef(false)
  const clockOffset = useMemo(() => snapshot ? new Date(snapshot.server_now).getTime() - now : 0, [snapshot?.server_now])

  const refresh = useCallback(async (advance = false) => {
    const next = advance ? await advanceGame(roomCode) : await getGameSnapshot(roomCode)
    setSnapshot(next)
    setError('')
    return next
  }, [roomCode])

  useEffect(() => {
    let stopped = false
    let unsubscribe: (() => void) | undefined
    let subscribedRoomId = ''

    const load = async (advance = false) => {
      if (busy.current) return
      busy.current = true
      try {
        const next = await refresh(advance)
        if (stopped) return
        if (subscribedRoomId !== next.room.id) {
          unsubscribe?.()
          subscribedRoomId = next.room.id
          unsubscribe = subscribeToGame(next.room.id, () => { void load() }, setConnection)
        }
      } catch (cause) {
        if (!stopped) setError(friendlyError(cause))
      } finally {
        busy.current = false
      }
    }

    void getLobbySnapshot(roomCode).then(() => load(true)).catch((cause) => {
      if (!stopped) setError(friendlyError(cause))
    })
    const progression = window.setInterval(() => { void load(true) }, 800)
    const heartbeat = window.setInterval(() => { void sendLobbyHeartbeat(roomCode).catch((cause) => { if (!stopped) setError(friendlyError(cause)) }) }, 25_000)
    const clock = window.setInterval(() => setNow(Date.now()), 150)
    return () => {
      stopped = true
      window.clearInterval(progression)
      window.clearInterval(heartbeat)
      window.clearInterval(clock)
      unsubscribe?.()
    }
  }, [refresh])

  const serverNow = now + clockOffset
  const round = snapshot?.round
  const countdownMs = snapshot?.game.countdown_ends_at
    ? new Date(snapshot.game.countdown_ends_at).getTime() - serverNow
    : 0
  const countNumber = Math.max(1, Math.ceil(countdownMs / 1000))
  const targetRemaining = round?.closes_at ? Math.max(0, new Date(round.closes_at).getTime() - serverNow) : 0
  const lastResolved = snapshot?.round_history.at(-1)
  const leadingScore = snapshot?.leaderboard[0]?.score ?? 0
  const tiedWinners = snapshot?.leaderboard.filter((player) => player.score === leadingScore) ?? []
  const isHost = snapshot?.room.host_player_id === snapshot?.current_player_id

  async function handleHit() {
    if (!snapshot || !round || round.status !== 'target_ready' || hitting) return
    setHitting(true)
    setFeedback('')
    try {
      setSnapshot(await submitHit(roomCode, snapshot.game.id, round.id))
    } catch (cause) {
      const message = friendlyError(cause)
      setFeedback(message)
      if (message.includes('no longer active')) {
        try { await refresh(true) } catch { /* the scheduled poll will retry */ }
      } else setError(message)
    } finally {
      setHitting(false)
    }
  }

  async function handlePlayAgain() {
    setReplaying(true)
    setError('')
    try {
      await startGame(roomCode)
      setSnapshot(await getGameSnapshot(roomCode))
      setFeedback('New run locked in. Get ready.')
    } catch (cause) {
      setError(friendlyError(cause))
    } finally {
      setReplaying(false)
    }
  }

  async function handleLeave() {
    setLeaving(true)
    try { await leaveRoom(roomCode); navigate('/') } catch (cause) { setError(friendlyError(cause)); setLeaving(false) }
  }

  if (!snapshot) return <PageTransition className="game-page"><div className="lobby-state-card"><span className="lobby-kicker">NEON RUSH / GAME LINK</span><h1>SYNCING<br /><span>THE ARENA.</span></h1><p>{error || 'Connecting to the shared game clock…'}</p>{error && <div className="lobby-state-actions"><Button to={`/room/${roomCode}`} variant="secondary">Return to lobby</Button><Button onClick={() => { setError(''); void refresh(true) }}>Reconnect</Button></div>}</div></PageTransition>

  const roundWinner = round?.status === 'resolved' ? snapshot.players.find((player) => player.id === round.winner_player_id) : undefined
  const lastWinnerId = lastResolved?.winner_player_id
  const lastWinnerName = lastResolved?.winner_name ?? snapshot.players.find((player) => player.id === lastWinnerId)?.display_name
  const isComplete = snapshot.game.status === 'completed'
  const canHit = snapshot.game.status === 'active' && round?.status === 'target_ready' && targetRemaining > 0 && !hitting
  const winnerLabel = tiedWinners.length > 1 ? 'DRAW' : tiedWinners[0]?.display_name ?? 'NO WINNER'

  return <PageTransition className="game-page">
    <header className="game-topline">
      <Link className="back-link" to={`/room/${roomCode}`}>← <span>ROOM {roomCode}</span></Link>
      <div className={`connection-pill ${connection === 'SUBSCRIBED' ? 'connection-online' : ''}`}><span />{connection === 'SUBSCRIBED' ? 'LIVE GAME' : connection}</div>
    </header>

    {isComplete ? <section className="results-panel">
      <div className="eyebrow"><span className="eyebrow-line" /> GAME {snapshot.game.game_number} / COMPLETE <span className="eyebrow-line" /></div>
      <h1>THE FASTEST<br /><span>HANDS WIN.</span></h1>
      <div className="winner-banner"><span>✦</span><div><small>{tiedWinners.length > 1 ? 'TOP OF THE BOARD' : 'ROUND CHAMPION'}</small><strong>{winnerLabel}</strong></div><b>{leadingScore}<i> / 10</i></b></div>
      <div className="leaderboard-card">
        <div className="leaderboard-heading"><span>FINAL LEADERBOARD</span><span>10 ROUNDS</span></div>
        {snapshot.leaderboard.map((player, index) => <div className="leaderboard-row" key={player.player_id}>
          <span className="leaderboard-rank">{String(index + 1).padStart(2, '0')}</span><span className="leaderboard-avatar">{player.display_name.slice(0, 1).toUpperCase()}</span><span className="leaderboard-name">{player.display_name}</span><span className="leaderboard-points">{player.score}<small> PTS</small></span>
        </div>)}
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      {isHost
        ? <Button fullWidth disabled={replaying} onClick={() => void handlePlayAgain()}>{replaying ? 'PREPARING…' : 'Play again'} <span className="button-arrow">↗</span></Button>
        : <div className="waiting-host"><span className="waiting-pulse" /> WAITING FOR HOST TO PLAY AGAIN</div>}
      <div className="game-result-actions"><Button to={`/room/${roomCode}`} variant="secondary">Back to room</Button><button type="button" onClick={() => void handleLeave()} disabled={leaving}>{leaving ? 'LEAVING…' : 'LEAVE ROOM'}</button></div>
    </section> : <>
      <div className="game-heading">
        <div><div className="eyebrow"><span className="eyebrow-line" /> LIVE REACTION PROTOCOL</div><h1>STAY SHARP.<br /><span>STRIKE FIRST.</span></h1></div>
        <div className="game-round-counter"><span>ROUND</span><strong>{String(Math.max(1, snapshot.game.current_round_number)).padStart(2, '0')}<i> / 10</i></strong></div>
      </div>
      <div className="game-layout">
        <section className="arena-card" aria-label="Reaction arena">
          <div className="arena-readout"><span>ARENA / {roomCode}</span><span>{snapshot.game.status === 'countdown' ? 'SYNCING START' : round?.status === 'target_ready' ? 'TARGET LIVE' : 'STANDBY'}</span></div>
          <div className={`arena-field${round?.status === 'target_ready' ? ' arena-live' : ''}`}>
            <div className="arena-grid" />
            {snapshot.game.status === 'countdown' ? <div className="arena-message"><span>STARTING IN</span><motion.strong key={countNumber} initial={{ scale: .6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ duration: .2 }}>{countdownMs > 0 ? countNumber : 'GO'}</motion.strong><small>SYNCED TO THE SERVER CLOCK</small></div>
              : round?.status === 'target_ready' && round.target_x !== null && round.target_y !== null && targetRemaining > 0
                ? <motion.button className="reaction-target" type="button" aria-label="Hit the target" style={{ left: `${round.target_x}%`, top: `${round.target_y}%` }} initial={{ scale: .2, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: .5, opacity: 0 }} transition={{ type: 'spring', stiffness: 420, damping: 20 }} onClick={() => void handleHit()} disabled={!canHit}><span className="target-ring target-ring-one" /><span className="target-ring target-ring-two" /><span className="target-dot" /></motion.button>
                : <div className="arena-message"><span>{round?.status === 'resolved' ? 'ROUND CLAIMED' : round?.status === 'expired' ? 'TARGET MISSED' : 'NEXT TARGET'}</span><strong className="arena-wait-mark">{round?.status === 'pending' ? '↯' : '·'}</strong><small>{round?.status === 'pending' ? 'STAY READY' : 'WAIT FOR THE SIGNAL'}</small></div>}
            {round?.status === 'target_ready' && <div className="target-timer"><span style={{ transform: `scaleX(${Math.min(1, targetRemaining / 2500)})` }} /></div>}
          </div>
          <div className="arena-caption"><span><i className="live-dot" /> SERVER-AUTHORITATIVE ROUND</span><span>{round?.status === 'target_ready' ? `${(targetRemaining / 1000).toFixed(1)} SEC` : 'WAIT FOR TARGET'}</span></div>
          {(feedback || error) && <p className="game-feedback" role="status">{feedback || error}</p>}
        </section>
        <aside className="game-sidebar">
          <div className="score-card"><div className="game-card-title"><span>LIVE SCOREBOARD</span><span>✦</span></div>{snapshot.leaderboard.map((player, index) => <div className="score-row" key={player.player_id}><span className="score-rank">{String(index + 1).padStart(2, '0')}</span><span className="score-player">{player.display_name}</span><strong>{player.score}</strong></div>)}<div className="score-foot">FIRST HIT TAKES THE POINT</div></div>
          <div className="round-feed"><div className="game-card-title"><span>ROUND FEED</span><span>10×</span></div>{lastResolved ? <div className="round-result"><span>ROUND {String(lastResolved.round_number).padStart(2, '0')}</span><strong>{lastResolved.status === 'expired' ? 'No hit' : `${lastWinnerName ?? 'Player'} scored`}</strong></div> : <p>First to hit the live target claims the round.</p>}<div className="round-progress" aria-label={`${snapshot.round_history.length} rounds completed`}>{Array.from({ length: 10 }, (_, index) => <span className={index < snapshot.round_history.length ? 'round-done' : ''} key={index} />)}</div></div>
          <button className="game-leave" type="button" onClick={() => void handleLeave()} disabled={leaving}>{leaving ? 'LEAVING…' : 'LEAVE GAME'}</button>
        </aside>
      </div>
      {roundWinner && <span className="sr-only">{roundWinner.display_name} won round {round?.round_number}</span>}
    </>}
  </PageTransition>
}
