"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { getFamily, searchGuests, submitRsvp, type FamilyMember, type GuestMatch } from "@/app/actions";
import { wedding } from "@/lib/config";
import { Cross, Divider } from "./Ornaments";
import Reveal from "./Reveal";

type Step = "search" | "confirm" | "done";

export default function Rsvp() {
  const [step, setStep] = useState<Step>("search");
  const [term, setTerm] = useState("");
  const [matches, setMatches] = useState<GuestMatch[]>([]);
  const [searching, setSearching] = useState(false);
  const [loadingFamily, setLoadingFamily] = useState(false);
  const [members, setMembers] = useState<FamilyMember[]>([]);
  const [attending, setAttending] = useState<Record<string, boolean>>({});
  const [note, setNote] = useState("");
  const [error, setError] = useState("");
  const [pending, start] = useTransition();
  const confirmRef = useRef<HTMLDivElement | null>(null);

  /* debounce the lookup so we aren't hitting the database on every keystroke */
  useEffect(() => {
    const q = term.trim();
    if (q.length < 2) {
      setMatches([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    const t = window.setTimeout(async () => {
      try {
        setMatches(await searchGuests(q));
      } catch {
        setMatches([]);
      } finally {
        setSearching(false);
      }
    }, 300);
    return () => window.clearTimeout(t);
  }, [term]);

  async function choose(g: GuestMatch) {
    setError("");
    setLoadingFamily(true);
    setStep("confirm");
    window.setTimeout(
      () => confirmRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }),
      60
    );

    const family = await getFamily(g.id);
    setLoadingFamily(false);

    if (!family) {
      setError("We couldn't load that invitation. Please search for your name again.");
      setStep("search");
      return;
    }

    setMembers(family.members);
    setNote(family.note);
    setAttending(
      Object.fromEntries(
        family.members.filter((m) => m.attending !== null).map((m) => [m.id, m.attending as boolean])
      )
    );
  }

  function send() {
    const responses = members
      .filter((m) => attending[m.id] !== undefined)
      .map((m) => ({ guestId: m.id, attending: attending[m.id] }));

    if (responses.length < members.length) {
      setError("Let us know whether each person will be joining, then send your reply.");
      return;
    }

    setError("");
    start(async () => {
      const res = await submitRsvp({ responses, note });
      if (res.ok) setStep("done");
      else setError(res.error);
    });
  }

  function restart() {
    setStep("search");
    setTerm("");
    setMatches([]);
    setMembers([]);
    setAttending({});
    setNote("");
    setError("");
  }

  const coming = members.filter((m) => attending[m.id] === true).map((m) => m.name);
  const notComing = members.filter((m) => attending[m.id] === false).map((m) => m.name);

  return (
    <Reveal className="section" >
      <div id="rsvp" className="anchor" />
      <p className="eyebrow eyebrow-rule">RSVP</p>
      <p className="lede">
        Find your name and let us know if you and your family can join us.
        Kindly reply by <strong>{wedding.rsvpBy}</strong>.
      </p>

      <div className="card rsvp">
        {step === "search" && (
          <div className="rsvp__step">
            <div className="field">
              <label htmlFor="guest-search">Your name</label>
              <input
                id="guest-search"
                type="text"
                autoComplete="off"
                spellCheck={false}
                value={term}
                onChange={(e) => setTerm(e.target.value)}
                placeholder="Start typing your first name"
              />
            </div>

            {searching && <p className="rsvp__hint">Looking&hellip;</p>}

            {!searching && matches.length > 0 && (
              <ul className="rsvp__results">
                {matches.map((m) => (
                  <li key={m.id}>
                    <button type="button" onClick={() => choose(m)}>
                      <span>{m.name}</span>
                      {m.replied && <em>replied</em>}
                    </button>
                  </li>
                ))}
              </ul>
            )}

            {!searching && term.trim().length >= 2 && matches.length === 0 && (
              <p className="rsvp__hint">
                We can&rsquo;t find that name. Try a different spelling, or the name
                exactly as it appears on your invitation.
              </p>
            )}
          </div>
        )}

        {step === "confirm" && (
          <div className="rsvp__step" ref={confirmRef}>
            {loadingFamily && <p className="rsvp__hint">Loading your invitation&hellip;</p>}

            {!loadingFamily && members.length > 0 && (
              <>
                <p className="rsvp__name">Will you be joining us?</p>
                <ul className="rsvp__family">
                  {members.map((m) => (
                    <li key={m.id} className="rsvp__member">
                      <span className="rsvp__member-name">{m.name}</span>
                      <span className="rsvp__member-choice" role="group" aria-label={`Is ${m.name} attending?`}>
                        <button
                          type="button"
                          aria-pressed={attending[m.id] === true}
                          onClick={() => setAttending((a) => ({ ...a, [m.id]: true }))}
                        >
                          Yes
                        </button>
                        <button
                          type="button"
                          aria-pressed={attending[m.id] === false}
                          onClick={() => setAttending((a) => ({ ...a, [m.id]: false }))}
                        >
                          No
                        </button>
                      </span>
                    </li>
                  ))}
                </ul>

                <div className="field">
                  <label htmlFor="note">Leave a note for the couple (optional)</label>
                  <textarea
                    id="note"
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="Can't wait! / So excited!!"
                  />
                </div>

                {error && <p className="rsvp__error">{error}</p>}

                <button className="btn" type="button" disabled={pending} onClick={send}>
                  {pending ? "Sending…" : "Send our reply"}
                </button>
              </>
            )}

            {!loadingFamily && members.length === 0 && error && <p className="rsvp__error">{error}</p>}

            <button className="link-underline" type="button" onClick={restart}>
              That&rsquo;s not me — search again
            </button>
          </div>
        )}

        {step === "done" && (
          <div className="rsvp__step rsvp__done">
            <Cross size={34} />
            <h3 className="rsvp__name">Thank you</h3>
            {coming.length > 0 && (
              <p className="lede">
                {coming.join(", ")} {coming.length === 1 ? "is" : "are"} down to celebrate with us on the 26th.
              </p>
            )}
            {notComing.length > 0 && (
              <p className="lede">{notComing.join(", ")} will be missed — thank you for letting us know.</p>
            )}
            <button className="link-underline" type="button" onClick={restart}>
              Change your reply
            </button>
          </div>
        )}
      </div>

      <Divider width={160} />
    </Reveal>
  );
}
