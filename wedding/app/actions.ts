"use server";

import { revalidatePath } from "next/cache";
import { db, dbConfigured, type Guest, type Wish } from "@/lib/supabase";

/* ── guest lookup ──────────────────────────────────────────────────────────
   Returns at most six matches. Nothing is returned for a query shorter than
   two characters, so the list can't be walked by typing a single letter.      */

export type GuestMatch = { id: string; name: string; seats: number; replied: boolean };

export async function searchGuests(term: string): Promise<GuestMatch[]> {
  const q = term.trim();
  if (q.length < 2 || !dbConfigured()) return [];

  const like = `%${q.replace(/[%_]/g, "")}%`;
  const { data, error } = await db()
    .from("guests")
    .select("id, name, seats, aliases, rsvps(attending)")
    .or(`name.ilike.${like},aliases.cs.{${q}}`)
    .limit(6);

  if (error) {
    console.error("guest search failed:", error.message);
    return [];
  }

  return (data ?? []).map((g: any) => ({
    id: g.id,
    name: g.name,
    seats: g.seats,
    replied: Array.isArray(g.rsvps) ? g.rsvps.length > 0 : Boolean(g.rsvps),
  }));
}

/* ── rsvp ─────────────────────────────────────────────────────────────────── */

export type RsvpResult = { ok: true; attending: boolean; party: number } | { ok: false; error: string };

export async function submitRsvp(input: {
  guestId: string;
  attending: boolean;
  partySize: number;
  note: string;
}): Promise<RsvpResult> {
  if (!dbConfigured()) {
    return { ok: false, error: "The RSVP list isn't connected yet. Please try again later." };
  }

  const { data: guest, error: lookupError } = await db()
    .from("guests")
    .select("id, seats")
    .eq("id", input.guestId)
    .single();

  if (lookupError || !guest) {
    return { ok: false, error: "We couldn't find that invitation. Please search for your name again." };
  }

  const party = input.attending
    ? Math.min(Math.max(1, Math.floor(input.partySize)), guest.seats)
    : 0;

  const { error } = await db().from("rsvps").upsert(
    {
      guest_id: guest.id,
      attending: input.attending,
      party_size: party,
      note: input.note.trim().slice(0, 600) || null,
    },
    { onConflict: "guest_id" }
  );

  if (error) {
    console.error("rsvp write failed:", error.message);
    return { ok: false, error: "Something went wrong saving your reply. Please try once more." };
  }

  revalidatePath("/admin");
  return { ok: true, attending: input.attending, party };
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
