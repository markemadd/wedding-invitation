"use server";

import { revalidatePath } from "next/cache";
import { dbConfigured, sql, type Wish } from "@/lib/db";

/* ── guest lookup ──────────────────────────────────────────────────────────
   Returns at most eight matches, one per person (not per family) — typing
   "Mark" should surface every Mark so the guest can tell them apart and pick
   themself. Nothing is returned for a query shorter than two characters, so
   the list can't be walked by typing a single letter.                        */

export type GuestMatch = { id: string; name: string; familyId: string; replied: boolean };

export async function searchGuests(term: string): Promise<GuestMatch[]> {
  const q = term.trim();
  if (q.length < 2 || !dbConfigured()) return [];

  try {
    const rows = (await sql()`
      select g.id, g.name, g.family_id, (r.guest_id is not null) as replied
      from guests g
      left join rsvps r on r.guest_id = g.id
      where g.name ilike ${"%" + q + "%"}
      order by
        case when g.name ilike ${q + "%"} then 0 else 1 end,
        g.name
      limit 8
    `) as any[];

    return rows.map((g) => ({
      id: g.id,
      name: g.name,
      familyId: g.family_id,
      replied: g.replied,
    }));
  } catch (err) {
    console.error("guest search failed:", err);
    return [];
  }
}

/* ── family lookup ────────────────────────────────────────────────────────
   Once a guest picks themself, this loads everyone who shares their
   family_id (a solo guest just gets a family of one) plus whatever they've
   already replied, so re-opening the RSVP shows their previous answers
   instead of a blank form.                                                  */

export type FamilyMember = { id: string; name: string; attending: boolean | null };

export async function getFamily(guestId: string): Promise<{ members: FamilyMember[]; note: string } | null> {
  if (!dbConfigured()) return null;

  try {
    const rows = (await sql()`
      select g.id, g.name, r.attending, r.note
      from guests g
      left join rsvps r on r.guest_id = g.id
      where g.family_id = (select family_id from guests where id = ${guestId})
      order by g.name
    `) as any[];

    if (!rows.length) return null;

    let note = "";
    const members = rows.map((g) => {
      if (g.note) note = g.note;
      return { id: g.id, name: g.name, attending: g.attending ?? null };
    });

    return { members, note };
  } catch (err) {
    console.error("family lookup failed:", err);
    return null;
  }
}

/* ── rsvp ─────────────────────────────────────────────────────────────────── */

export type RsvpResult = { ok: true } | { ok: false; error: string };

export async function submitRsvp(input: {
  responses: { guestId: string; attending: boolean }[];
  note: string;
}): Promise<RsvpResult> {
  if (!dbConfigured()) {
    return { ok: false, error: "The RSVP list isn't connected yet. Please try again later." };
  }
  if (!input.responses.length) {
    return { ok: false, error: "Let us know whether each person is coming." };
  }

  const note = input.note.trim().slice(0, 600) || null;
  const ids = input.responses.map((r) => r.guestId);
  const attending = input.responses.map((r) => r.attending);

  try {
    /* unnest turns the two parallel arrays into rows, so the whole family is
       written in one round trip instead of one query per person */
    await sql()`
      insert into rsvps (guest_id, attending, note)
      select id, att, ${note}
      from unnest(${ids}::uuid[], ${attending}::boolean[]) as t(id, att)
      on conflict (guest_id) do update
        set attending = excluded.attending,
            note = excluded.note,
            updated_at = now()
    `;
  } catch (err) {
    console.error("rsvp write failed:", err);
    return { ok: false, error: "Something went wrong saving your reply. Please try once more." };
  }

  revalidatePath("/admin");
  return { ok: true };
}

/* ── wishes ───────────────────────────────────────────────────────────────── */

export async function listWishes(): Promise<Wish[]> {
  if (!dbConfigured()) return [];

  try {
    const rows = (await sql()`
      select id, name, message, created_at
      from wishes
      where approved
      order by created_at desc
      limit 50
    `) as any[];
    return rows as Wish[];
  } catch (err) {
    console.error("wish list failed:", err);
    return [];
  }
}

export async function sendWish(input: { name: string; message: string }) {
  const name = input.name.trim().slice(0, 80);
  const message = input.message.trim().slice(0, 600);

  if (!name || !message) {
    return { ok: false as const, error: "Please add both your name and a message." };
  }
  if (!dbConfigured()) {
    return { ok: false as const, error: "Wishes aren't connected yet. Please try again later." };
  }

  try {
    /* approved defaults to false — the wall is public, so a wish waits for
       the couple to release it in /admin before anyone else can read it */
    await sql()`insert into wishes (name, message) values (${name}, ${message})`;
  } catch (err) {
    console.error("wish write failed:", err);
    return { ok: false as const, error: "Something went wrong sending your wish. Please try once more." };
  }

  revalidatePath("/admin");
  return { ok: true as const };
}

/* ── moderation ───────────────────────────────────────────────────────────
   Server actions are ordinary POST endpoints — anyone can call one if they
   know it exists — so these re-check the admin key themselves rather than
   trusting that the caller came from the admin page.                       */

function isAdmin(key: string): boolean {
  const secret = process.env.ADMIN_KEY;
  return Boolean(secret) && key === secret;
}

export async function listAllWishes(key: string): Promise<(Wish & { approved: boolean })[]> {
  if (!isAdmin(key) || !dbConfigured()) return [];

  try {
    const rows = (await sql()`
      select id, name, message, approved, created_at
      from wishes
      order by approved, created_at desc
    `) as any[];
    return rows;
  } catch (err) {
    console.error("wish moderation list failed:", err);
    return [];
  }
}

export async function setWishApproved(key: string, id: string, approved: boolean) {
  if (!isAdmin(key)) return { ok: false as const, error: "Not authorised." };

  try {
    await sql()`update wishes set approved = ${approved} where id = ${id}`;
  } catch (err) {
    console.error("wish approve failed:", err);
    return { ok: false as const, error: "Could not update that wish." };
  }

  revalidatePath("/");
  revalidatePath("/admin");
  return { ok: true as const };
}

export async function deleteWish(key: string, id: string) {
  if (!isAdmin(key)) return { ok: false as const, error: "Not authorised." };

  try {
    await sql()`delete from wishes where id = ${id}`;
  } catch (err) {
    console.error("wish delete failed:", err);
    return { ok: false as const, error: "Could not delete that wish." };
  }

  revalidatePath("/");
  revalidatePath("/admin");
  return { ok: true as const };
}
