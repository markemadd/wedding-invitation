"use client";

import { useState, useTransition } from "react";
import { sendWish, listWishes } from "@/app/actions";
import type { Wish } from "@/lib/db";
import { Corner } from "./Ornaments";
import Reveal from "./Reveal";

function when(iso: string) {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

export default function Wishes({ initial }: { initial: Wish[] }) {
  const [wishes, setWishes] = useState<Wish[]>(initial);
  const [name, setName] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);
  const [pending, start] = useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    start(async () => {
      const res = await sendWish({ name, message });
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setSent(true);
      setName("");
      setMessage("");
      setWishes(await listWishes());
    });
  }

  return (
    <Reveal className="section">
      <p className="eyebrow eyebrow-rule">Guest Wishes</p>

      <div className="card wishes">
        <span className="wishes__corner"><Corner corner="tr" /></span>

        <form className="wishes__form" onSubmit={submit}>
          <div className="field">
            <label htmlFor="wish-name">Your name</label>
            <input
              id="wish-name"
              type="text"
              required
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Your name"
            />
          </div>

          <div className="field">
            <label htmlFor="wish-body">Your wish for the couple</label>
            <textarea
              id="wish-body"
              required
              maxLength={600}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Write something they'll read on the morning of the wedding."
            />
          </div>

          {error && <p className="rsvp__error">{error}</p>}
          {sent && !error && <p className="wishes__sent">Thank you — your wish is below.</p>}

          <button className="btn" type="submit" disabled={pending}>
            {pending ? "Sending…" : "Send Wish"}
          </button>
        </form>
      </div>

      {wishes.length > 0 && (
        <ul className="wishes__list">
          {wishes.map((w) => (
            <li key={w.id}>
              <div className="wishes__head">
                <strong>{w.name}</strong>
                <time dateTime={w.created_at}>{when(w.created_at)}</time>
              </div>
              <p>{w.message}</p>
            </li>
          ))}
        </ul>
      )}
    </Reveal>
  );
}
