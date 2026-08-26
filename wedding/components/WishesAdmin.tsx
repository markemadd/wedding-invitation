"use client";

import { useState, useTransition } from "react";
import { deleteWish, setWishApproved } from "@/app/actions";
import type { Wish } from "@/lib/db";

type Row = Wish & { approved: boolean };

/**
 * Moderation for the public wishes wall. Nothing a guest writes is visible on
 * the invitation until it is approved here.
 */
export default function WishesAdmin({ adminKey, initial }: { adminKey: string; initial: Row[] }) {
  const [rows, setRows] = useState<Row[]>(initial);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [, start] = useTransition();

  function approve(id: string, approved: boolean) {
    setBusy(id);
    setError("");
    start(async () => {
      const res = await setWishApproved(adminKey, id, approved);
      if (res.ok) setRows((r) => r.map((w) => (w.id === id ? { ...w, approved } : w)));
      else setError(res.error);
      setBusy(null);
    });
  }

  function remove(id: string) {
    setBusy(id);
    setError("");
    start(async () => {
      const res = await deleteWish(adminKey, id);
      if (res.ok) setRows((r) => r.filter((w) => w.id !== id));
      else setError(res.error);
      setBusy(null);
    });
  }

  const waiting = rows.filter((w) => !w.approved);
  const live = rows.filter((w) => w.approved);

  return (
    <section className="admin__wishes">
      <h2>
        Guest wishes
        {waiting.length > 0 && <span className="pill pill--none">{waiting.length} awaiting review</span>}
      </h2>

      {error && <p className="rsvp__error">{error}</p>}

      {rows.length === 0 && <p className="lede">No wishes have been sent yet.</p>}

      {[
        { key: "waiting", label: "Awaiting your approval", list: waiting },
        { key: "live", label: "Showing on the invitation", list: live },
      ].map(({ key, label, list }) =>
        list.length ? (
          <div key={key} className="admin__wish-group">
            <h3>{label}</h3>
            <ul className="admin__wish-list">
              {list.map((w) => (
                <li key={w.id}>
                  <div>
                    <b>{w.name}</b>
                    <time>
                      {new Date(w.created_at).toLocaleDateString("en-GB", {
                        day: "numeric",
                        month: "short",
                      })}
                    </time>
                    <p>{w.message}</p>
                  </div>
                  <div className="admin__wish-actions">
                    <button
                      type="button"
                      className="btn btn--quiet"
                      disabled={busy === w.id}
                      onClick={() => approve(w.id, !w.approved)}
                    >
                      {w.approved ? "Hide" : "Approve"}
                    </button>
                    <button
                      type="button"
                      className="link-underline"
                      disabled={busy === w.id}
                      onClick={() => remove(w.id)}
                    >
                      Delete
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        ) : null
      )}
    </section>
  );
}
