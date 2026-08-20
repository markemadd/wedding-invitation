/**
 * Applies db/schema.sql to the Neon database.
 *
 *   npm run migrate
 *
 * The schema is written with `if not exists` / `create or replace` throughout,
 * so running it again is safe and non-destructive.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("Set DATABASE_URL first (vercel env pull .env.local).");
  process.exit(1);
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schema = readFileSync(path.join(__dirname, "..", "db", "schema.sql"), "utf8");

/* Split on semicolons that end a statement, keeping $$ … $$ function bodies
   intact — the trigger functions in the schema contain their own semicolons. */
function statements(text) {
  const out = [];
  let buf = "";
  let inDollar = false;

  for (const line of text.split("\n")) {
    if (line.trim().startsWith("--") && !inDollar) continue;
    const dollars = (line.match(/\$\$/g) ?? []).length;
    if (dollars % 2 === 1) inDollar = !inDollar;
    buf += line + "\n";
    if (!inDollar && line.trimEnd().endsWith(";")) {
      if (buf.trim()) out.push(buf.trim());
      buf = "";
    }
  }
  if (buf.trim()) out.push(buf.trim());
  return out;
}

const sql = neon(url);
const parts = statements(schema);

console.log(`Applying ${parts.length} statements…`);
for (const statement of parts) {
  try {
    await sql.query(statement);
  } catch (err) {
    console.error("\nFailed on:\n" + statement + "\n→ " + err.message);
    process.exit(1);
  }
}
console.log("Schema applied.");
