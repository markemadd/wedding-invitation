"use server";

import { revalidatePath } from "next/cache";
import { db, dbConfigured, type Guest, type Wish } from "@/lib/supabase";

/* ── guest lookup ──────────────────────────────────────────────────────────
   Returns at most eight matches, one per person (not per family) — typing
   "Mark" should surface every Mark so the guest can tell them apart and pick
   themself. Nothing is returned for a query shorter than two characters, so
   the list can't be walked by typing a single letter.                        */

export type GuestMatch = { id: string; name: string; familyId: string; replied: boolean };

export async function searchGuests(term: string): Promise<GuestMatch[]> {
  const q = term.trim();
  if (q.length < 2 || !dbConfigured()) return [];

  const like = `%${q.replace(/[%_]/g, "")}%`;
  const { data, error } = await db()
    .from("guests")
    .select("id, name, family_id, rsvps(attending)")
    .ilike("name", like)
    .order("name")
    .limit(8);

  if (error) {
    console.error("guest search failed:", error.message);
    return [];
  }

  return (data ?? []).map((g: any) => ({
    id: g.id,
    name: g.name,
    familyId: g.family_id,
    replied: Array.isArray(g.rsvps) ? g.rsvps.length > 0 : Boolean(g.rsvps),
  }));
}

/* ── family lookup ────────────────────────────────────────────────────────
   Once a guest picks themself, this loads everyone who shares their
   family_id (a solo guest just gets a family of one) plus whatever they've
   already replied, so re-opening the RSVP shows their previous answers
   instead of a blank form.                                                  */

export type FamilyMember = { id: string; name: string; attending: boolean | null };

export async function getFamily(guestId: string): Promise<{ members: FamilyMember[]; note: string } | null> {
  if (!dbConfigured()) return null;

  const { data: guest, error: guestError } = await db()
    .from("guests")
    .select("family_id")
    .eq("id", guestId)
    .single();

  if (guestError || !guest) return null;

  const { data, error } = await db()
    .from("guests")
    .select("id, name, rsvps(attending, note)")
    .eq("family_id", guest.family_id)
    .order("name");

  if (error) {
    console.error("family lookup failed:", error.message);
    return null;
  }

  let note = "";
  const members = (data ?? []).map((g: any) => {
    const rsvp = Array.isArray(g.rsvps) ? g.rsvps[0] : g.rsvps;
    if (rsvp?.note) note = rsvp.note;
    return { id: g.id, name: g.name, attending: rsvp ? rsvp.attending : null };
  });

  return { members, note };
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
  const rows = input.responses.map((r) => ({ guest_id: r.guestId, attending: r.attending, note }));

  const { error } = await db().from("rsvps").upsert(rows, { onConflict: "guest_id" });

  if (error) {
    console.error("rsvp write failed:", error.message);
    return { ok: false, error: "Something went wrong saving your reply. Please try once more." };
  }

  revalidatePath("/admin");
  return { ok: true };
}

/* ── wishes ───────────────────────────────────────────────────────────────── */

export async function listWishes(): Promise<Wish[]> {
  if (!dbConfigured()) return [];

  const { data, error } = await db()
    .from("wishes")
    .select("id, name, message, created_at")
    .eq("approved", true)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    console.error("wish list failed:", error.message);
    return [];
  }
  return data ?? [];
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

  const { error } = await db().from("wishes").insert({ name, message });
  if (error) {
    console.error("wish write failed:", error.message);
    return { ok: false as const, error: "Something went wrong sending your wish. Please try once more." };
  }

  revalidatePath("/");
  return { ok: true as const };
}
