# Maria & Joseph — wedding invitation

A one-page invitation with a real RSVP database. Next.js 14 (App Router) +
Supabase. Guests find their own name in the guest list, accept or decline, and
leave a wish; you watch the headcount at `/admin`.

Everything about the day — names, times, venues, schedule, gift link — lives in
[`lib/config.ts`](lib/config.ts). Edit that file, not the components.

---

## 1. Run it locally

```sh
cd wedding
npm install
npm run dev                    # http://localhost:3000
```

That is the whole first run — no configuration needed to look at it. Without
Supabase credentials the RSVP search finds nobody ("we can't find that name")
and sending a wish reports that wishes aren't connected yet. Nothing errors,
and every other part of the page is exactly what gets deployed. Add
`.env.local` when you want the database (step 2).

**To open it on your phone,** bind the dev server to your network and visit
your Mac's LAN address from the phone — same Wi-Fi, no deployment involved:

```sh
npm run dev -- -H 0.0.0.0
ipconfig getifaddr en0        # your Mac's address, e.g. 192.168.1.20
```

Then browse to `http://192.168.1.20:3000` on the phone. This is the honest way
to judge it, since almost every guest will open the invitation on a phone.

## 2. Set up the database

1. Create a free project at [supabase.com](https://supabase.com).
2. Open **SQL Editor → New query**, paste all of
   [`supabase/schema.sql`](supabase/schema.sql), and run it. That creates
   `guests`, `rsvps`, and `wishes`, and locks all three behind RLS.
3. Go to **Project Settings → API** and copy into `.env.local`:
   - `SUPABASE_URL` — the Project URL
   - `SUPABASE_SERVICE_ROLE_KEY` — the **service_role** key, not `anon`
4. Invent a long random string for `ADMIN_KEY`.

The service role key bypasses RLS, so it must stay server-side. Every database
call in this app runs inside a server action ([`app/actions.ts`](app/actions.ts))
— the key is never sent to the browser, and the guest list is never downloadable
as a whole. Never rename the variable to `NEXT_PUBLIC_…`.

## 3. Load the guest list

Write a CSV with one row per **invitation** (a household, not a person):

```csv
name,seats,aliases,side,phone
"Mr. & Mrs. Nabil Boutros",2,"Nabil;Boutros",groom,
"Dr. Mina Fawzy & Family",5,"Mina",bride,
"Ms. Sandra Youssef",1,,both,
```

- `name` — exactly as printed on the invitation; this is what guests search for
- `seats` — the cap on how many people that invitation may bring
- `aliases` — optional extra spellings, separated by `;`, so search still finds
  them if someone types only a first or family name
- `side`, `phone` — optional, for your own reference

Then:

```sh
export SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=...
node scripts/seed-guests.mjs guests.csv
```

Re-running is safe — a name that already exists is updated, not duplicated. So
you can add people in batches as the list firms up.

## 4. Watch the replies

Open `/admin?key=YOUR_ADMIN_KEY` for the live headcount: guests coming,
accepted, declined, still waiting, plus every note guests left. It's a plain
URL guard, not real authentication — treat the link as the secret and don't
post it anywhere public.

## 5. Deploy

Push the repo to GitHub and import it at [vercel.com](https://vercel.com), with
**Root Directory** set to `wedding`. Add `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, and `ADMIN_KEY` as environment variables, then
deploy. Point a domain at it and send the link out.

---

## Still to fill in

These are all in `lib/config.ts`, and every one degrades politely until set —
buttons read "coming soon" rather than breaking.

| Field | What it's for |
| --- | --- |
| `parents.*.address` | Optional addresses under the parents' names in Ceremony Info. |
| `closingNote` | The adults-only note at the foot of the page. `null` removes it. |
| `ceremony.mapUrl` | Google Maps link for the church. |
| `reception.mapUrl` | Google Maps link for the JW Marriott. |
| `reception.time` | Currently a placeholder `18:00`. |
| `giftUrl` | The gift-list redirection link. |
| `music` | Optional track, e.g. `/music.mp3` in `public/`. No file = no music button. |

## Notes on the design

Section order follows the Chateau Green template: cover gate → hero → ceremony
info → reception info → calendar → venue + map → schedule → RSVP → gifts →
wishes → closing. The template's photo gallery is replaced by the gift section
until there are engagement photos to show.

### The artwork

Two images in `public/` carry the whole look:

- `garden.png` — the watercolour garden pavilion, used at the foot of the hero
  and again to close the page
- `crest.png` — the crowned gilt oval, holding the couple's initials on the
  cover gate

Both were recovered from a screen recording, so they are 1080px and 510px wide
respectively and are deliberately never displayed larger than that. `.garden`
in `app/globals.css` sets a `min-width` floor and crops at the viewport edges
rather than upscaling. If a higher-resolution original turns up, drop it in at
the same filename and the floor can be raised.

**Source.** The art came from a Pinterest collage, i.e. it is someone else's
work and is not licensed for this use. Fine for a private, unlisted family
invitation; worth replacing with a licensed copy if this ever goes public.

**The palette is sampled from `garden.png`,** not chosen independently — gilt
from the fountain and the crest, blue from the tiled dome, greens from the
cypress and palm, and the page's paper colour from the wash the mural floats
on. The values are listed at the top of `app/globals.css`. Swap the artwork and
those values need resampling, or the page and the picture will drift apart.

The smaller botanicals in [`components/Ornaments.tsx`](components/Ornaments.tsx)
are drawn as SVG so they recolour with the palette and cost nothing to load.

Typography is Cormorant Garamond over EB Garamond, both self-hosted at build
time by `next/font` — no runtime request to Google. Palette lives at the top of
[`app/globals.css`](app/globals.css) as CSS custom properties.
