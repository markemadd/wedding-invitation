/**
 * Loads the guest list into Supabase from a CSV.
 *
 *   node scripts/seed-guests.mjs guests.csv
 *
 * CSV columns (header row required):
 *   name,seats,aliases,side,phone
 *
 *   name    — exactly as printed on the invitation, e.g. "Mr. & Mrs. Nabil Boutros"
 *   seats   — how many people that invitation covers
 *   aliases — optional, semicolon-separated extra spellings: "Nabil;Boutros"
 *   side    — optional: bride | groom | both
 *   phone   — optional
 *
 * Re-running is safe: a name that already exists is updated, not duplicated.
 */

import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const file = process.argv[2];

if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.");
  process.exit(1);
}
if (!file) {
  console.error("Usage: node scripts/seed-guests.mjs guests.csv");
  process.exit(1);
}

/** Minimal CSV reader — handles quoted fields and embedded commas. */
function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (c !== "\r") cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((v) => v.trim()));
}

const rows = parseCsv(readFileSync(file, "utf8"));
const header = rows.shift().map((h) => h.trim().toLowerCase());
const col = (name) => header.indexOf(name);

const guests = rows.map((r) => {
  const seats = Number(r[col("seats")]) || 1;
  const aliases = (col("aliases") > -1 ? r[col("aliases")] : "")
    .split(";")
    .map((s) => s.trim())
    .filter(Boolean);

  return {
    name: r[col("name")].trim(),
    seats,
    aliases,
    side: col("side") > -1 ? r[col("side")].trim() || null : null,
    phone: col("phone") > -1 ? r[col("phone")].trim() || null : null,
  };
});

const bad = guests.filter((g) => !g.name);
if (bad.length) {
  console.error(`${bad.length} row(s) have no name — fix the CSV and try again.`);
  process.exit(1);
}

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
    ? await supabase.from("guests").update(g).eq("id", id)
    : await supabase.from("guests").insert(g);

  if (error) {
    console.error(`  ✗ ${g.name}: ${error.message}`);
    continue;
  }
  id ? updated++ : inserted++;
}

console.log(`${inserted} added, ${updated} updated, ${guests.length} rows in the file.`);
