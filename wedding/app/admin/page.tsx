import { db, dbConfigured } from "@/lib/supabase";

/** Live headcount — never cached. */
export const dynamic = "force-dynamic";

type Row = {
  id: string;
  name: string;
  seats: number;
  rsvps: { attending: boolean; party_size: number; note: string | null; updated_at: string } | null;
};

export default async function Admin({
  searchParams,
}: {
  searchParams: { key?: string };
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
        <p className="lede">Supabase isn&rsquo;t configured yet — see wedding/README.md.</p>
      </main>
    );
  }

  const { data, error } = await db()
    .from("guests")
    .select("id, name, seats, rsvps(attending, party_size, note, updated_at)")
    .order("name");

  if (error) {
    return (
      <main className="admin">
        <h1>Admin</h1>
        <p className="lede">Could not read the guest list: {error.message}</p>
      </main>
    );
  }

  const rows = (data ?? []).map((r: any) => ({
    ...r,
    rsvps: Array.isArray(r.rsvps) ? r.rsvps[0] ?? null : r.rsvps,
  })) as Row[];

  const coming = rows.reduce((n, r) => n + (r.rsvps?.attending ? r.rsvps.party_size : 0), 0);
  const yes = rows.filter((r) => r.rsvps?.attending).length;
  const no = rows.filter((r) => r.rsvps && !r.rsvps.attending).length;
  const waiting = rows.length - yes - no;

  return (
    <main className="admin">
      <h1>Guest list</h1>

      <div className="admin__tiles">
        <div className="admin__tile"><b>{coming}</b><small>Guests coming</small></div>
        <div className="admin__tile"><b>{yes}</b><small>Accepted</small></div>
        <div className="admin__tile"><b>{no}</b><small>Declined</small></div>
        <div className="admin__tile"><b>{waiting}</b><small>No reply yet</small></div>
        <div className="admin__tile"><b>{rows.length}</b><small>Invitations</small></div>
      </div>

      <div className="admin__table-wrap">
        <table>
          <thead>
            <tr>
              <th>Invitation</th>
              <th>Seats</th>
              <th>Reply</th>
              <th>Coming</th>
              <th>Note</th>
              <th>Replied</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td>{r.name}</td>
                <td>{r.seats}</td>
                <td>
                  {!r.rsvps && <span className="pill pill--none">Waiting</span>}
                  {r.rsvps?.attending && <span className="pill pill--yes">Accepts</span>}
                  {r.rsvps && !r.rsvps.attending && <span className="pill pill--no">Declines</span>}
                </td>
                <td>{r.rsvps?.attending ? r.rsvps.party_size : "—"}</td>
                <td className="wrap">{r.rsvps?.note ?? ""}</td>
                <td>
                  {r.rsvps
                    ? new Date(r.rsvps.updated_at).toLocaleDateString("en-GB", {
                        day: "numeric",
                        month: "short",
                      })
                    : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
