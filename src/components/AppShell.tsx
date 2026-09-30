import type { ReactNode } from 'react'
import { Link, NavLink } from 'react-router-dom'

export function AppShell({ children }: { children: ReactNode }) {
  return <div className="app-shell">
    <div className="ambient ambient-one" /><div className="ambient ambient-two" />
    <header className="topbar">
      <Link className="brand" to="/" aria-label="Neon Rush home"><span className="brand-mark" aria-hidden="true"><span /></span><span>NEON<span className="brand-light">RUSH</span></span></Link>
      <nav className="topnav" aria-label="Main navigation"><NavLink to="/create">Create room</NavLink><NavLink to="/join">Join room</NavLink></nav>
      <div className="status-pill"><span className="status-dot" /> LIVE ARCADE</div>
    </header>
    <main className="main-content">{children}</main>
    <footer className="site-footer"><span>NO DOWNLOADS. NO ACCOUNTS. JUST REFLEXES.</span><span className="footer-right"><span className="footer-spark">✦</span> MADE FOR THE MOMENT</span></footer>
  </div>
}
