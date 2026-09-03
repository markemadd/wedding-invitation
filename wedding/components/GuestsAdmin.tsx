"use client";

import { useState, useTransition } from "react";
import { addGuest } from "@/app/actions";

type Option = { id: string; name: string };

/**
 * One-off additions to the guest list, for when re-exporting the spreadsheet
 * is more trouble than it is worth. Rows added here are marked 'manual', so
 * re-importing the spreadsheet later leaves them alone.
 */
export default function GuestsAdmin({ adminKey, guests }: { adminKey: string; guests: Option[] }) {
  const [name, setName] = useState("");
  const [linkName, setLinkName] = useState("");
  const [error, setError] = useState("");
  const [done, setDone] = useState<{ name: string; family: string[] } | null>(null);
  const [pending, start] = useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setDone(null);

    let linkToGuestId: string | undefined;
    const wanted = linkName.trim().toLowerCase();
    if (wanted) {
      const match = guests.find((g) => g.name.toLowerCase() === wanted);
      if (!match) {
        setError(`"${linkName.trim()}" isn't on the guest list — pick a name from the suggestions, or leave it blank.`);
        return;
      }
      linkToGuestId = match.id;
    }

    start(async () => {
      const res = await addGuest({ key: adminKey, name, linkToGuestId });
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setDone({ name: res.name, family: res.family });
      setName("");
      setLinkName("");
    });
  }

  return (
    <section className="admin__add">
      <h2>Add a guest</h2>

      <form className="admin__add-form" onSubmit={submit}>
        <div className="field">
          <label htmlFor="new-guest">Full name</label>
          <input
            id="new-guest"
            type="text"
            value={name}
            maxLength={120}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Sara Adel"
          />
        </div>

        <div className="field">
          <label htmlFor="link-guest">Add to whose family? (optional)</label>
          <input
            id="link-guest"
            type="text"
            list="guest-names"
            value={linkName}
            onChange={(e) => setLinkName(e.target.value)}
            placeholder="Leave blank if they're on their own"
          />
          <datalist id="guest-names">
            {guests.map((g) => (
              <option key={g.id} value={g.name} />
            ))}
          </datalist>
        </div>

        <button className="btn" type="submit" disabled={pending || !name.trim()}>
          {pending ? "Adding…" : "Add guest"}
        </button>
      </form>

      {error && <p className="rsvp__error">{error}</p>}

      {done && (
        <p className="admin__add-done">
          Added <strong>{done.name}</strong>
          {done.family.length > 1 ? (
            <> — their family now reads {done.family.join(", ")}.</>
          ) : (
            <> as a guest on their own. Reload to see them in the list.</>
          )}
        </p>
      )}
    </section>
  );
}
