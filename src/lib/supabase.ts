import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim()
const supabasePublicKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
  || import.meta.env.VITE_SUPABASE_ANON_KEY?.trim()

export const supabaseConfigurationAvailable = Boolean(supabaseUrl && supabasePublicKey)

export const supabase = supabaseConfigurationAvailable
  ? createClient(supabaseUrl!, supabasePublicKey!, {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
      },
    })
  : null

let anonymousSessionPromise: ReturnType<typeof createAnonymousSession> | null = null

async function createAnonymousSession() {
  if (!supabase) throw new Error('Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY in .env.local.')

  const { data: sessionData, error: sessionError } = await supabase.auth.getSession()
  if (sessionError) throw sessionError
  if (sessionData.session) return sessionData.session

  const { data, error } = await supabase.auth.signInAnonymously()
  if (error) {
    if (error.message.toLowerCase().includes('anonymous')) {
      throw new Error('Anonymous sign-in is not enabled for this Supabase project. Enable it in Authentication → Providers → Anonymous.')
    }
    throw error
  }
  if (!data.session) throw new Error('Supabase did not create an anonymous player session.')
  return data.session
}

export async function ensureAnonymousSession() {
  if (!anonymousSessionPromise) {
    anonymousSessionPromise = createAnonymousSession().finally(() => {
      anonymousSessionPromise = null
    })
  }
  return anonymousSessionPromise
}
