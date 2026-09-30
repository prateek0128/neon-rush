import { lazy, Suspense } from 'react'
import { AnimatePresence } from 'framer-motion'
import { Route, Routes, useLocation } from 'react-router-dom'
import { AppShell } from './components/AppShell'

const HomePage = lazy(() => import('./pages/HomePage').then(({ HomePage }) => ({ default: HomePage })))
const CreateRoomPage = lazy(() => import('./pages/CreateRoomPage').then(({ CreateRoomPage }) => ({ default: CreateRoomPage })))
const JoinRoomPage = lazy(() => import('./pages/JoinRoomPage').then(({ JoinRoomPage }) => ({ default: JoinRoomPage })))
const LobbyPage = lazy(() => import('./pages/LobbyPage').then(({ LobbyPage }) => ({ default: LobbyPage })))
const GamePage = lazy(() => import('./pages/GamePage').then(({ GamePage }) => ({ default: GamePage })))

export default function App() {
  const location = useLocation()
  return <AppShell><AnimatePresence mode="wait"><Suspense fallback={<div className="route-loading" aria-label="Loading Neon Rush" />}><Routes location={location} key={location.pathname}>
    <Route path="/" element={<HomePage />} />
    <Route path="/create" element={<CreateRoomPage />} />
    <Route path="/join" element={<JoinRoomPage />} />
    <Route path="/room/:roomCode" element={<LobbyPage />} />
    <Route path="/room/:roomCode/game" element={<GamePage />} />
    <Route path="*" element={<HomePage />} />
  </Routes></Suspense></AnimatePresence></AppShell>
}
