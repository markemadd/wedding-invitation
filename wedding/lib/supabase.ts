import { createClient, SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-only Supabase client.
 *
 * The service role key bypasses RLS, so it must never reach the browser — every
 * call goes through a server action in app/actions.ts. That also means the full
 * guest list is never downloadable: search runs on the server and returns only
 * the rows that matched.
 */
let client: SupabaseClient | null = null;

export function db(): SupabaseClient {
  if (client) return client;

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error(
      "Supabase is not configured. Copy .env.example to .env.local and fill in " +
        "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY."
    );
  }

  client = createClient(url, key, { auth: { persistSession: false } });
  return client;
}

/** True when the site has database credentials; the UI degrades politely if not. */
export function dbConfigured(): boolean {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

export type Guest = {
  id: string;
  name: string;
  family_id: string;
};

export type Wish = {
  id: string;
  name: string;
  message: string;
  created_at: string;
};
