-- ============================================================================
--  Joseph & Maria — guest list + RSVP schema
--  Run once against the Neon database (npm run migrate).
-- ============================================================================

create extension if not exists pg_trgm;
create extension if not exists "pgcrypto";

-- ── guests ──────────────────────────────────────────────────────────────────
-- One row per PERSON (not per household). Linked people — a couple, a family —
-- share a family_id. A solo guest gets a family_id equal to nobody else's,
-- i.e. a "family" of one; this keeps the RSVP flow (and every query) uniform
-- instead of having to special-case guests with no listed family.
create table if not exists public.guests (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  family_id   uuid not null default gen_random_uuid(),
  created_at  timestamptz not null default now()
);

-- Fuzzy substring search over the name, so "Mark" finds every Mark.
create index if not exists guests_name_trgm_idx
  on public.guests using gin (lower(name) gin_trgm_ops);
create index if not exists guests_family_idx on public.guests (family_id);

-- ── rsvps ───────────────────────────────────────────────────────────────────
-- One row per guest, so each person in a family can be marked attending or
-- not individually. `note` is the one shared message the family leaves when
-- they reply together — it's written identically onto every row in that
-- family's submission, which keeps the query for "show me a family's reply"
-- a single indexed lookup instead of a join into a separate notes table.
create table if not exists public.rsvps (
  guest_id    uuid primary key references public.guests(id) on delete cascade,
  attending   boolean not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists rsvps_touch on public.rsvps;
create trigger rsvps_touch before update on public.rsvps
  for each row execute function public.touch_updated_at();

-- ── wishes ──────────────────────────────────────────────────────────────────
-- Unrelated to the RSVP note above — this is the separate public guestbook
-- wall on the site.
create table if not exists public.wishes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  message     text not null check (char_length(message) between 1 and 600),
  approved    boolean not null default true,  -- flip to false to pre-moderate
  created_at  timestamptz not null default now()
);

create index if not exists wishes_recent_idx on public.wishes (created_at desc);

-- No row-level security needed: the database is reachable only through
-- DATABASE_URL, which lives on the server and is never shipped to the browser.
-- Every read and write goes through a server action in app/actions.ts.
