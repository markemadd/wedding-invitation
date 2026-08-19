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
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const file = process.argv[2];

if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.");
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

const guests = [];
for (const members of groups.values()) {
  const family_id = randomUUID();
  for (const name of members) guests.push({ name, family_id });
}

console.log(`${guests.length} guests across ${groups.size} families in the file.`);

/* ── upsert ──────────────────────────────────────────────────────────────── */

const supabase = createClient(url, key, { auth: { persistSession: false } });

const { data: existing, error: readError } = await supabase.from("guests").select("id, name");
if (readError) {
  console.error("Could not read the existing list:", readError.message);
  process.exit(1);
}

const byName = new Map((existing ?? []).map((g) => [g.name.toLowerCase(), g.id]));

let inserted = 0;
let updated = 0;

for (const g of guests) {
  const id = byName.get(g.name.toLowerCase());
  const { error } = id
    ? await supabase.from("guests").update({ name: g.name, family_id: g.family_id }).eq("id", id)
    : await supabase.from("guests").insert(g);

  if (error) {
    console.error(`  ✗ ${g.name}: ${error.message}`);
    continue;
  }
  id ? updated++ : inserted++;
}

console.log(`${inserted} added, ${updated} updated, ${guests.length} guests in the file.`);
