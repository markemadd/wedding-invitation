"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { searchGuests, submitRsvp, type GuestMatch } from "@/app/actions";
import { wedding } from "@/lib/config";
import { Cross, Divider } from "./Ornaments";
import Reveal from "./Reveal";

type Step = "search" | "confirm" | "done";

export default function Rsvp() {
  const [step, setStep] = useState<Step>("search");
  const [term, setTerm] = useState("");
  const [matches, setMatches] = useState<GuestMatch[]>([]);
  const [searching, setSearching] = useState(false);
  const [guest, setGuest] = useState<GuestMatch | null>(null);
  const [attending, setAttending] = useState<boolean | null>(null);
  const [party, setParty] = useState(1);
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

  function choose(g: GuestMatch) {
    setGuest(g);
    setAttending(null);
    setParty(g.seats);
    setNote("");
    setError("");
    setStep("confirm");
    window.setTimeout(
      () => confirmRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }),
      60
    );
  }

  function send() {
    if (!guest || attending === null) return;
    setError("");
    start(async () => {
      const res = await submitRsvp({
        guestId: guest.id,
        attending,
        partySize: attending ? party : 0,
        note,
      });
      if (res.ok) setStep("done");
      else setError(res.error);
    });
  }

  function restart() {
    setStep("search");
    setTerm("");
    setMatches([]);
    setGuest(null);
    setAttending(null);
    setError("");
  }

  return (
    <Reveal className="section" >
      <div id="rsvp" className="anchor" />
      <p className="eyebrow eyebrow-rule">RSVP</p>
      <p className="lede">
        Find the name on your invitation and let us know if you can join us.
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
                placeholder="Start typing your name or family name"
              />
            </div>

            {searching && <p className="rsvp__hint">Looking&hellip;</p>}

            {!searching && matches.length > 0 && (
              <ul className="rsvp__results">
                {matches.map((m) => (
                  <li key={m.id}>
                    <button type="button" onClick={() => choose(m)}>
                      <span>{m.name}</span>
                      <em>
                        {m.seats} {m.seats === 1 ? "seat" : "seats"}
                        {m.replied ? " · replied" : ""}
                      </em>
                    </button>
                  </li>
                ))}
              </ul>
            )}

            {!searching && term.trim().length >= 2 && matches.length === 0 && (
              <p className="rsvp__hint">
                We can&rsquo;t find that name. Try your family name, or the name exactly
                as it appears on your invitation.
              </p>
            )}
          </div>
        )}

        {step === "confirm" && guest && (
          <div className="rsvp__step" ref={confirmRef}>
            <p className="rsvp__name">{guest.name}</p>
            <p className="rsvp__seats">
              Your invitation is for {guest.seats} {guest.seats === 1 ? "guest" : "guests"}
            </p>

            <div className="field">
              <label id="attend-label">Will you be joining us?</label>
              <div className="choice" role="group" aria-labelledby="attend-label">
                <button
                  type="button"
                  aria-pressed={attending === true}
                  onClick={() => setAttending(true)}
                >
                  Joyfully accepts
                </button>
                <button
                  type="button"
                  aria-pressed={attending === false}
                  onClick={() => setAttending(false)}
                >
                  Regretfully declines
                </button>
              </div>
            </div>

            {attending === true && guest.seats > 1 && (
              <div className="field">
                <label htmlFor="party">How many of you?</label>
                <select id="party" value={party} onChange={(e) => setParty(Number(e.target.value))}>
                  {Array.from({ length: guest.seats }, (_, i) => i + 1).map((n) => (
                    <option key={n} value={n}>
                      {n === 1 ? "Just me" : `${n} of us`}
                    </option>
                  ))}
                </select>
              </div>
            )}

            <div className="field">
              <label htmlFor="note">A note for the couple (optional)</label>
              <textarea
                id="note"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Dietary needs, a blessing, anything you'd like us to know."
              />
            </div>

            {error && <p className="rsvp__error">{error}</p>}

            <button className="btn" type="button" disabled={attending === null || pending} onClick={send}>
              {pending ? "Sending…" : "Send our reply"}
            </button>
            <button className="link-underline" type="button" onClick={restart}>
              That&rsquo;s not me — search again
            </button>
          </div>
        )}

        {step === "done" && (
          <div className="rsvp__step rsvp__done">
            <Cross size={34} />
            <h3 className="rsvp__name">{attending ? "Wonderful" : "We’ll miss you"}</h3>
            <p className="lede">
              {attending
                ? `We have you down for ${party} ${party === 1 ? "seat" : "seats"}. See you on the 26th.`
                : "Thank you for letting us know — you'll be in our thoughts on the day."}
            </p>
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
