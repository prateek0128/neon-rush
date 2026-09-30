import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '../components/Button'
import { Field } from '../components/Field'
import { PageTransition } from '../components/PageTransition'
import { createRoom } from '../lib/rooms'

export function CreateRoomPage() {
  const [name, setName] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const navigate = useNavigate()

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      const lobby = await createRoom(name)
      navigate(`/room/${lobby.room.code}`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Unable to create a room. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return <PageTransition className="form-page">
    <Link className="back-link" to="/">← <span>Back to home</span></Link>
    <div className="form-layout">
      <div className="form-intro"><div className="eyebrow"><span className="eyebrow-line" /> START A NEW GAME</div><h1>CALL THE<br /><span>ARENA.</span></h1><p>Set your name. Bring your people.<br />The fastest one takes the crown.</p>
        <div className="mini-stats"><span><b>02–08</b> PLAYERS</span><span className="mini-divider" /><span><b>10</b> ROUNDS</span><span className="mini-divider" /><span><b>0</b> DOWNLOADS</span></div>
      </div>
      <form className="form-card" onSubmit={handleSubmit}><div className="card-topline"><span>PLAYER SETUP</span><span className="step-count">01 <i>/</i> 01</span></div><div className="card-heading"><h2>Who’s playing?</h2><p>Choose the name your friends will see.</p></div>
        <Field label="DISPLAY NAME" name="displayName" placeholder="e.g. quicksilver" maxLength={18} autoComplete="nickname" value={name} onChange={(event) => setName(event.target.value)} leading={<span className="user-glyph">◉</span>} />
        <div className="room-note"><span className="note-icon">✳</span><p>Your private lobby will be ready to share as soon as it’s created.</p></div>
        {error && <p className="form-error" role="alert">{error}</p>}
        <Button type="submit" fullWidth disabled={!name.trim() || submitting}>{submitting ? 'Creating room…' : 'Create room'} <span className="button-arrow">↗</span></Button><p className="form-footnote">NO ACCOUNT NEEDED <span>·</span> SESSION SAVED IN THIS BROWSER</p>
      </form>
    </div><div className="form-decoration" aria-hidden="true"><span>NR</span><i /></div>
  </PageTransition>
}
