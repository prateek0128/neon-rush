import { motion } from 'framer-motion'
import { Button } from '../components/Button'
import { PageTransition } from '../components/PageTransition'

const bars = [32, 54, 39, 70, 49, 84, 57, 43, 72, 50, 91, 62, 45, 77, 56, 96, 67, 48, 81, 57, 73, 43, 88, 60, 75, 51, 92, 64, 47, 79, 58, 86, 46, 69, 52, 95]

export function HomePage() {
  return <PageTransition className="home-page">
    <div className="hero-copy">
      <div className="eyebrow"><span className="eyebrow-line" /> THE REAL-TIME REFLEX ARENA <span className="eyebrow-line" /></div>
      <h1>DON’T THINK.<br /><span>JUST</span> <span className="headline-pop">HIT.</span></h1>
      <p className="hero-description">One target. A room full of rivals.<br className="desktop-break" /> How fast are your reflexes, really?</p>
      <div className="hero-actions"><Button to="/create">Create a room <span className="button-arrow">↗</span></Button><Button to="/join" variant="secondary">Join with a code</Button></div>
      <div className="hero-meta"><div className="avatar-stack" aria-hidden="true"><span>J</span><span>M</span><span>A</span><span>+</span></div><span>PLAY WITH <strong>2–8 FRIENDS</strong></span><span className="meta-divider" /><span className="instant-mark">↯</span><span>READY IN SECONDS</span></div>
    </div>
    <div className="hero-art" aria-label="Neon target with reaction wave visual">
      <div className="art-label art-label-top"><span>REACTION<br />PROTOCOL</span><span className="art-label-id">NR—01</span></div>
      <div className="orbit orbit-outer" /><div className="orbit orbit-mid" /><div className="orbit orbit-inner" />
      <div className="crosshair crosshair-horizontal" /><div className="crosshair crosshair-vertical" />
      <motion.div className="target-core" animate={{ scale: [1, 1.06, 1], opacity: [.92, 1, .92] }} transition={{ duration: 2.4, repeat: Infinity, ease: 'easeInOut' }}><div className="target-core-inner"><span /></div></motion.div>
      <div className="target-marker marker-a">+</div><div className="target-marker marker-b">+</div>
      <div className="art-label art-label-bottom"><span><i className="live-dot" /> TARGET ACQUIRED</span><span>00:00:01.24</span></div>
      <div className="waveform" aria-hidden="true">{bars.map((height, index) => <span key={index} style={{ height: `${height}%`, animationDelay: `${(index % 8) * -0.17}s` }} />)}</div>
      <div className="art-corner corner-tl" /><div className="art-corner corner-tr" /><div className="art-corner corner-bl" /><div className="art-corner corner-br" /><span className="art-side-label">REACTION TIME / MS</span>
    </div>
    <div className="hero-bottomline"><span>001 — 010 ROUNDS</span><span className="bottomline-track"><i /></span><span>FIRST HIT WINS</span></div>
  </PageTransition>
}
