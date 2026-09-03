/**
 * Loads the guest list into Supabase from the wedding's .xlsx export.
 *
 *   node scripts/seed-guests.mjs "Wedding Guest List.xlsx"
 *
 * Expected columns: Name, Families.
 *   name     — exactly as it should appear when someone searches for themself
 *   families — filled in on ONE row per linked group, e.g.
 *              "Menna Ghalwash & Amr Abdelghani" — everyone else in that
 *              group leaves Families blank. A name with no Families entry
 *              (anywhere) is treated as a solo guest.
 *
 * A name mentioned only inside a Families cell (e.g. a plus-one like
 * "Salwa +1" with no row of its own) still gets its own guest record.
 *
 * Re-running is safe: a name that already exists is updated, not duplicated.
 * The .xlsx itself is never committed to the repo — it's read from wherever
 * you point this script at it.
 */

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
const file = process.argv[2];

if (!url) {
  console.error("Set DATABASE_URL first (vercel env pull .env.local).");
  process.exit(1);
}
if (!file) {
  console.error('Usage: node scripts/seed-guests.mjs "Wedding Guest List.xlsx"');
  process.exit(1);
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reader = path.join(__dirname, "read-xlsx.py");

let rows;
try {
  const json = execFileSync("python3", [reader, file], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  rows = JSON.parse(json);
} catch (err) {
  console.error("Could not read the .xlsx file:", err.message);
  process.exit(1);
}

if (!rows.length) {
  console.error("No rows with a name were found in that file.");
  process.exit(1);
}

/* ── union-find over names, merged by shared Families cells ────────────── */

const parent = new Map(); // normalized name -> normalized name
const display = new Map(); // normalized name -> the name as it should be shown

function norm(name) {
  return name.trim().replace(/\s+/g, " ").toLowerCase();
}

function register(name) {
  const clean = name.trim().replace(/\s+/g, " ");
  const key = norm(clean);
  if (!parent.has(key)) {
    parent.set(key, key);
    display.set(key, clean);
  }
  return key;
}

function find(key) {
  while (parent.get(key) !== key) {
    parent.set(key, parent.get(parent.get(key)));
    key = parent.get(key);
  }
  return key;
}

function union(a, b) {
  const ra = find(a);
  const rb = find(b);
  if (ra !== rb) parent.set(ra, rb);
}

for (const row of rows) {
  const selfKey = register(row.name);
  if (!row.families) continue;

  const members = row.families
    .split("&")
    .map((s) => s.trim())
    .filter(Boolean);

  const keys = members.map(register);
  for (const k of keys) union(selfKey, k);
}

/* ── group into families, assign one family_id per group ────────────────── */

const groups = new Map(); // root key -> array of display names
for (const key of parent.keys()) {
  const root = find(key);
  if (!groups.has(root)) groups.set(root, []);
  groups.get(root).push(display.get(key));
}

console.log(`${[...groups.values()].flat().length} guests across ${groups.size} families in the file.`);

/* ── upsert ──────────────────────────────────────────────────────────────── */

const sql = neon(url);

const existing = await sql`select id, lower(name) as key, family_id, source from guests`;
const byName = new Map(existing.map((g) => [g.key, g.id]));
const familyByName = new Map(existing.map((g) => [g.key, g.family_id]));

/* Reuse the family_id a group already has rather than minting a fresh one
   every run. Stable ids matter because a guest added by hand in /admin joins
   a family by copying its id — churn it here and the next import silently
   orphans them. Where a group's members arrive carrying different ids (two
   families merged in the spreadsheet) the most common one wins. */
const guests = [];
for (const members of groups.values()) {
  const seen = new Map();
  for (const name of members) {
    const id = familyByName.get(name.toLowerCase());
    if (id) seen.set(id, (seen.get(id) ?? 0) + 1);
  }
  const family_id = seen.size
    ? [...seen.entries()].sort((a, b) => b[1] - a[1])[0][0]
    : randomUUID();
  for (const name of members) guests.push({ name, family_id });
}

const toInsert = guests.filter((g) => !byName.has(g.name.toLowerCase()));
const toUpdate = guests.filter((g) => byName.has(g.name.toLowerCase()));

if (toInsert.length) {
  await sql`
    insert into guests (name, family_id, source)
    select *, 'excel' from unnest(${toInsert.map((g) => g.name)}::text[], ${toInsert.map((g) => g.family_id)}::uuid[])
  `;
}

if (toUpdate.length) {
  await sql`
    update guests g
    set family_id = t.family_id
    from unnest(${toUpdate.map((g) => byName.get(g.name.toLowerCase()))}::uuid[],
                ${toUpdate.map((g) => g.family_id)}::uuid[]) as t(id, family_id)
    where g.id = t.id
  `;
}

/* ── prune ────────────────────────────────────────────────────────────────
   A guest renamed in the spreadsheet ("Hakim" → "Hakim Magdy") reads here as
   one insert plus one row nobody points at any more, so stale rows have to
   go or they linger in the search forever. Two things are never pruned:
   guests added by hand in /admin, who were never in the file to begin with,
   and anyone who has already replied — losing a real RSVP to a spelling
   change is never the right trade.                                          */

const inFile = new Set(guests.map((g) => g.name.toLowerCase()));
const stale = existing.filter((g) => g.source === "excel" && !inFile.has(g.key));

let deleted = 0;
if (stale.length) {
  const staleIds = stale.map((g) => g.id);
  const answered = await sql`
    select g.id, g.name from guests g
    join rsvps r on r.guest_id = g.id
    where g.id = any(${staleIds}::uuid[])
  `;
  const keep = new Set(answered.map((g) => g.id));
  const removable = staleIds.filter((id) => !keep.has(id));

  if (removable.length) {
    await sql`delete from guests where id = any(${removable}::uuid[])`;
    deleted = removable.length;
  }
  if (answered.length) {
    console.warn(
      `\n  ! ${answered.length} guest(s) are no longer in the file but have already replied — ` +
        `left in place:\n    ${answered.map((g) => g.name).join(", ")}\n`
    );
  }
}

console.log(
  `${toInsert.length} added, ${toUpdate.length} updated, ${deleted} removed, ` +
    `${guests.length} guests in the file.`
);
