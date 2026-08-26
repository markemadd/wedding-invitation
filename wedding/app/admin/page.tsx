import { listAllWishes } from "@/app/actions";
import WishesAdmin from "@/components/WishesAdmin";
import { dbConfigured, sql } from "@/lib/db";

/** Live headcount — never cached. */
export const dynamic = "force-dynamic";

type Row = {
  id: string;
  name: string;
  family_id: string;
  attending: boolean | null;
  note: string | null;
  updated_at: string | null;
};

type Status = "all" | "yes" | "no" | "pending";

function statusOf(r: Row): Exclude<Status, "all"> {
  if (r.attending === null) return "pending";
  return r.attending ? "yes" : "no";
}

/** A minimal, dependency-free donut — three status slices, always labelled
 *  directly so nobody has to match a legend color by eye. */
function Donut({ yes, no, pending }: { yes: number; no: number; pending: number }) {
  const total = yes + no + pending || 1;
  const r = 60;
  const c = 2 * Math.PI * r;
  const slices = [
    { key: "yes", value: yes, color: "#F3B093", label: "Coming" },
    { key: "no", value: no, color: "#9A3B2F", label: "Not coming" },
    { key: "pending", value: pending, color: "#A89C90", label: "No reply yet" },
  ];

  let offset = 0;
  const arcs = slices.map((s) => {
    const frac = s.value / total;
    const dash = frac * c;
    const arc = { ...s, dash, gap: c - dash, offset };
    offset -= dash;
    return arc;
  });

  return (
    <div className="admin__chart">
      <svg viewBox="0 0 160 160" width="160" height="160" role="img" aria-label="RSVP status breakdown">
        <circle cx="80" cy="80" r={r} fill="none" stroke="var(--ivory-dim)" strokeWidth="20" />
        {arcs.map((a) =>
          a.value > 0 ? (
            <circle
              key={a.key}
              cx="80"
              cy="80"
              r={r}
              fill="none"
              stroke={a.color}
              strokeWidth="20"
              strokeDasharray={`${a.dash} ${a.gap}`}
              strokeDashoffset={a.offset}
              transform="rotate(-90 80 80)"
              strokeLinecap="butt"
            />
          ) : null
        )}
        <text x="80" y="75" textAnchor="middle" className="admin__chart-num">
          {yes + no}
        </text>
        <text x="80" y="93" textAnchor="middle" className="admin__chart-label">
          replied
        </text>
      </svg>
      <ul className="admin__legend">
        {slices.map((s) => (
          <li key={s.key}>
            <span className="admin__swatch" style={{ background: s.color }} aria-hidden="true" />
            {s.label} — <strong>{s.value}</strong> ({Math.round((s.value / total) * 100)}%)
          </li>
        ))}
      </ul>
    </div>
  );
}

export default async function Admin({
  searchParams,
}: {
  searchParams: { key?: string; status?: string; q?: string };
}) {
  const secret = process.env.ADMIN_KEY;

  if (!secret) {
    return (
      <main className="admin">
        <h1>Admin</h1>
        <p className="lede">
          Set <code>ADMIN_KEY</code> in your environment, then open{" "}
          <code>/admin?key=…</code> with that value.
        </p>
      </main>
    );
  }

  if (searchParams.key !== secret) {
    return (
      <main className="admin">
        <h1>Admin</h1>
        <p className="lede">Add <code>?key=…</code> to the URL to see the guest list.</p>
      </main>
    );
  }

  if (!dbConfigured()) {
    return (
      <main className="admin">
        <h1>Admin</h1>
        <p className="lede">The database isn&rsquo;t connected yet — see wedding/README.md.</p>
      </main>
    );
  }

  let rows: Row[];
  let wishes: Awaited<ReturnType<typeof listAllWishes>> = [];
  try {
    rows = (await sql()`
      select g.id, g.name, g.family_id, r.attending, r.note, r.updated_at
      from guests g
      left join rsvps r on r.guest_id = g.id
      order by g.name
    `) as Row[];
    wishes = await listAllWishes(searchParams.key);
  } catch (err) {
    return (
      <main className="admin">
        <h1>Admin</h1>
        <p className="lede">Could not read the guest list: {String(err)}</p>
      </main>
    );
  }

  const familyNames = new Map<string, string[]>();
  for (const r of rows) {
    const list = familyNames.get(r.family_id) ?? [];
    list.push(r.name);
    familyNames.set(r.family_id, list);
  }

  const yes = rows.filter((r) => statusOf(r) === "yes").length;
  const no = rows.filter((r) => statusOf(r) === "no").length;
  const pending = rows.filter((r) => statusOf(r) === "pending").length;

  const status: Status = (["yes", "no", "pending"] as const).includes(searchParams.status as any)
    ? (searchParams.status as Status)
    : "all";
  const q = (searchParams.q ?? "").trim().toLowerCase();

  const filtered = rows.filter((r) => {
    if (status !== "all" && statusOf(r) !== status) return false;
    if (q && !r.name.toLowerCase().includes(q)) return false;
    return true;
  });

  const key = searchParams.key;
  const linkTo = (params: Record<string, string>) => {
    const usp = new URLSearchParams({ key, status, q: searchParams.q ?? "", ...params });
    return `/admin?${usp.toString()}`;
  };

  return (
    <main className="admin">
      <h1>Guest list</h1>

      <div className="admin__tiles">
        <div className="admin__tile"><b>{rows.length}</b><small>Invited</small></div>
        <div className="admin__tile"><b>{yes + no}</b><small>Responded</small></div>
        <div className="admin__tile"><b>{pending}</b><small>No reply yet</small></div>
        <div className="admin__tile"><b>{yes}</b><small>Coming</small></div>
        <div className="admin__tile"><b>{no}</b><small>Not coming</small></div>
      </div>

      <Donut yes={yes} no={no} pending={pending} />

      <form className="admin__filters" action="/admin" method="get">
        <input type="hidden" name="key" value={key} />
        <div className="admin__filter-pills">
          {(["all", "yes", "no", "pending"] as const).map((s) => (
            <a
              key={s}
              href={linkTo({ status: s })}
              className={`pill admin__filter-pill ${status === s ? "is-active" : ""}`}
            >
              {s === "all" ? "All" : s === "yes" ? "Coming" : s === "no" ? "Not coming" : "No reply"}
            </a>
          ))}
        </div>
        <input
          type="search"
          name="q"
          defaultValue={searchParams.q ?? ""}
          placeholder="Search a name…"
          aria-label="Search guests by name"
        />
        <button className="btn btn--quiet" type="submit">Search</button>
      </form>

      <div className="admin__table-wrap">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Family</th>
              <th>Reply</th>
              <th>Note</th>
              <th>Replied</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r) => {
              const others = (familyNames.get(r.family_id) ?? []).filter((n) => n !== r.name);
              return (
                <tr key={r.id}>
                  <td>{r.name}</td>
                  <td className="wrap">{others.join(", ")}</td>
                  <td>
                    {r.attending === null && <span className="pill pill--none">Waiting</span>}
                    {r.attending === true && <span className="pill pill--yes">Coming</span>}
                    {r.attending === false && <span className="pill pill--no">Not coming</span>}
                  </td>
                  <td className="wrap">{r.note ?? ""}</td>
                  <td>
                    {r.updated_at
                      ? new Date(r.updated_at).toLocaleDateString("en-GB", {
                          day: "numeric",
                          month: "short",
                        })
                      : "—"}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {filtered.length === 0 && <p className="lede">No guests match that filter.</p>}
      </div>

      <WishesAdmin adminKey={key} initial={wishes} />
    </main>
  );
}
