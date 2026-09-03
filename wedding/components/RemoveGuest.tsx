"use client";

import { useState, useTransition } from "react";
import { removeGuest } from "@/app/actions";

/**
 * Row-level delete. Deleting cascades to the guest's RSVP, so a guest who has
 * already replied has to be confirmed twice — the first click only warns.
 */
export default function RemoveGuest({
  adminKey,
  id,
  name,
  hasReplied,
}: {
  adminKey: string;
  id: string;
  name: string;
  hasReplied: boolean;
}) {
  const [armed, setArmed] = useState(false);
  const [gone, setGone] = useState(false);
  const [error, setError] = useState("");
  const [pending, start] = useTransition();

  if (gone) return <span className="admin__removed">Removed</span>;

  function click() {
    if (!armed) {
      setArmed(true);
      return;
    }
    setError("");
    start(async () => {
      const res = await removeGuest(adminKey, id);
      if (res.ok) setGone(true);
      else setError(res.error);
      setArmed(false);
    });
  }

  return (
    <>
      <button
        type="button"
        className={`admin__remove ${armed ? "is-armed" : ""}`}
        disabled={pending}
        onClick={click}
        title={
          hasReplied
            ? `${name} has already replied — removing them deletes their reply too`
            : `Remove ${name}`
        }
      >
        {pending ? "…" : armed ? (hasReplied ? "Delete reply too?" : "Sure?") : "Remove"}
      </button>
      {armed && !pending && (
        <button type="button" className="admin__remove-cancel" onClick={() => setArmed(false)}>
          Cancel
        </button>
      )}
      {error && <span className="admin__remove-error">{error}</span>}
    </>
  );
}
