# Neon Rush

Neon Rush is a browser-based multiplayer reaction game. The project uses React, TypeScript, Vite, and Supabase. The current multiplayer foundation provides anonymous browser sessions, transactional room membership, and a realtime lobby; reaction gameplay is not implemented yet.

## Development

```sh
npm install
npm run dev
```

Room creation and joining use Supabase RPCs, and the lobby is backed by Supabase Realtime. This phase has no target clicking or scoring.

Set the project URL and public client key in `.env.local` at the project root:

```env
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

The legacy `VITE_SUPABASE_ANON_KEY` variable is also accepted during key migration. Never use a Supabase secret or `service_role` key in Vite. Enable anonymous sign-ins in Supabase Authentication settings, then apply the database migration with `supabase db push` after linking the Supabase CLI to the project. The migration adds `rooms`, `players`, `games`, and `rounds` with RLS policies and server-side RPCs.

## Production build

```sh
npm run build
npm run preview
```

Database tests use Supabase's local stack and Docker:

```sh
supabase start
npm test
```
