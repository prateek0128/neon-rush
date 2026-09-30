import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '../components/Button'
import { Field } from '../components/Field'
import { PageTransition } from '../components/PageTransition'
import { joinRoom } from '../lib/rooms'

export function JoinRoomPage() {
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const navigate = useNavigate()

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      const lobby = await joinRoom(name, code)
      navigate(`/room/${lobby.room.code}`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Unable to join this room. Check the code and try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return <PageTransition className="form-page">
    <Link className="back-link" to="/">← <span>Back to home</span></Link>
    <div className="form-layout join-layout">
      <div className="form-intro"><div className="eyebrow"><span className="eyebrow-line" /> YOU’RE INVITED</div><h1>THE GAME<br /><span>IS ON.</span></h1><p>Your crew’s waiting. Drop in and<br />see who’s really got the reflexes.</p>
        <div className="invite-stamp"><span className="stamp-icon">↗</span><span>ROOM CODE<br /><b>FROM YOUR HOST</b></span></div>
      </div>
      <form className="form-card" onSubmit={handleSubmit}><div className="card-topline"><span>JOIN A ROOM</span><span className="step-count">01 <i>/</i> 01</span></div><div className="card-heading"><h2>Jump in.</h2><p>Enter the code your host shared with you.</p></div>
        <Field label="ROOM CODE" name="roomCode" placeholder="A1B2C3D4" maxLength={8} autoCapitalize="characters" autoComplete="off" value={code} onChange={(event) => setCode(event.target.value.replace(/[^a-f0-9]/gi, '').toUpperCase())} leading={<span className="code-glyph">⌗</span>} />
        <Field label="DISPLAY NAME" name="displayName" placeholder="e.g. quicksilver" maxLength={18} autoComplete="nickname" value={name} onChange={(event) => setName(event.target.value)} leading={<span className="user-glyph">◉</span>} />
        {error && <p className="form-error" role="alert">{error}</p>}
        <Button type="submit" fullWidth disabled={code.length !== 8 || !name.trim() || submitting}>{submitting ? 'Joining room…' : 'Join room'} <span className="button-arrow">↗</span></Button><p className="form-footnote">NO ACCOUNT NEEDED <span>·</span> SESSION SAVED IN THIS BROWSER</p>
      </form>
    </div><div className="form-decoration" aria-hidden="true"><span>NR</span><i /></div>
  </PageTransition>
}
