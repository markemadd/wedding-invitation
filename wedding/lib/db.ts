import { neon } from "@neondatabase/serverless";

/**
 * Server-only Postgres access (Neon, provisioned through Vercel Storage).
 *
 * DATABASE_URL is injected by the Vercel integration. Every call goes through
 * a server action in app/actions.ts, so the connection string never reaches
 * the browser and the full guest list is never downloadable — search runs on
 * the server and returns only the rows that matched.
 */
let client: ReturnType<typeof neon> | null = null;

export function sql() {
  if (client) return client;

  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error(
      "DATABASE_URL is not set. Provision Neon from the Vercel dashboard " +
        "(Storage → Create Database), or add it to .env.local for local work."
    );
  }

  client = neon(url);
  return client;
}

/** True when the site has a database connection; the UI degrades politely if not. */
export function dbConfigured(): boolean {
  return Boolean(process.env.DATABASE_URL);
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
