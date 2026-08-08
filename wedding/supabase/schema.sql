-- ============================================================================
--  Maria & Joseph — RSVP schema
--  Run this once in the Supabase SQL editor (Dashboard → SQL → New query).
-- ============================================================================

-- ── guests ──────────────────────────────────────────────────────────────────
-- One row per invitation (a household), not per person.
create table if not exists public.guests (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,                 -- as printed on the invitation
  seats       int  not null default 2 check (seats between 1 and 20),
  aliases     text[] not null default '{}',  -- extra spellings so search finds them
  side        text check (side in ('bride', 'groom', 'both')),
  phone       text,
  created_at  timestamptz not null default now()
);

-- Fuzzy substring search over the printed name (aliases are matched in SQL too).
create extension if not exists pg_trgm;
create index if not exists guests_name_trgm_idx
  on public.guests using gin (lower(name) gin_trgm_ops);

-- ── rsvps ───────────────────────────────────────────────────────────────────
-- One row per guest. A guest who replies twice updates their row.
create table if not exists public.rsvps (
  guest_id    uuid primary key references public.guests(id) on delete cascade,
  attending   boolean not null,
  party_size  int not null default 0 check (party_size >= 0),
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

-- A party can never exceed the seats on the invitation.
create or replace function public.check_party_size()
returns trigger language plpgsql as $$
declare allowed int;
begin
  select seats into allowed from public.guests where id = new.guest_id;
  if new.attending and new.party_size > allowed then
    raise exception 'party_size % exceeds the % seat(s) on this invitation',
      new.party_size, allowed;
  end if;
  return new;
end $$;

drop trigger if exists rsvps_party_size on public.rsvps;
create trigger rsvps_party_size before insert or update on public.rsvps
  for each row execute function public.check_party_size();

-- ── wishes ──────────────────────────────────────────────────────────────────
create table if not exists public.wishes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  message     text not null check (char_length(message) between 1 and 600),
  approved    boolean not null default true,  -- flip to false to pre-moderate
  created_at  timestamptz not null default now()
);

create index if not exists wishes_recent_idx on public.wishes (created_at desc);

-- ── row level security ──────────────────────────────────────────────────────
-- The site talks to Supabase only from the server, using the service role key,
-- so no policy grants the anon key anything. Lock all three tables down.
alter table public.guests enable row level security;
alter table public.rsvps  enable row level security;
alter table public.wishes enable row level security;

-- (No policies = no anon access. The service role bypasses RLS by design.)

-- ── headcount view, for the admin page ──────────────────────────────────────
create or replace view public.rsvp_summary as
select
  count(*) filter (where r.attending)                        as households_yes,
  count(*) filter (where not r.attending)                    as households_no,
  coalesce(sum(r.party_size) filter (where r.attending), 0)  as guests_coming,
  (select count(*) from public.guests)                       as households_invited,
  (select coalesce(sum(seats), 0) from public.guests)        as seats_invited
from public.rsvps r;
