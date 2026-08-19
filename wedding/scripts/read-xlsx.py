#!/usr/bin/env python3
"""
Reads a guest-list .xlsx and prints [{"name": ..., "families": ...}, ...] as
JSON. Expects columns Name and Families (any sheet, any column order — the
header row is matched by name). Called from seed-guests.mjs so the import
script never depends on a JS xlsx-parsing package.
"""
import json
import sys

import openpyxl

path = sys.argv[1]
wb = openpyxl.load_workbook(path, data_only=True)
ws = wb.worksheets[0]

rows = list(ws.iter_rows(values_only=True))

header_idx = None
cols = {}
for i, row in enumerate(rows):
    lowered = [str(c).strip().lower() if c is not None else "" for c in row]
    if "name" in lowered:
        header_idx = i
        cols = {name: lowered.index(name) for name in ("name", "families") if name in lowered}
        break

if header_idx is None:
    print("Could not find a header row containing a 'Name' column.", file=sys.stderr)
    sys.exit(1)

out = []
for row in rows[header_idx + 1:]:
    name = row[cols["name"]] if cols.get("name") is not None else None
    if not name or not str(name).strip():
        continue
    families = row[cols["families"]] if "families" in cols else None
    out.append({
        "name": str(name).strip(),
        "families": str(families).strip() if families and str(families).strip() else None,
    })

print(json.dumps(out))
