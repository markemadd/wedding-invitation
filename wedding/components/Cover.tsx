"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { couple, wedding } from "@/lib/config";
import crest from "@/public/crest.png";
import engagement from "@/public/engagement.jpg";
import envelopeClosed from "@/public/envelope-closed.jpg";
import envelopeOpenImg from "@/public/envelope-open.jpg";
import monogram from "@/public/monogram.png";
import { Corner } from "./Ornaments";

/**
 * The gate. Covers the page on load; "Open Invitation" lifts it away and
 * releases the scroll — the same beat as the reference template.
 */
export default function Cover({ onOpen }: { onOpen: () => void }) {
  const [envelopeOpen, setEnvelopeOpen] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [gone, setGone] = useState(false);

  useEffect(() => {
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
    };
  }, []);

  function open() {
    setLeaving(true);
    document.body.style.overflow = "";
    onOpen();
    window.setTimeout(() => setGone(true), 1100);
  }

  if (gone) return null;

  return (
    <div className={`cover ${leaving ? "cover--leaving" : ""}`} role="dialog" aria-label="Wedding invitation">
      <div className="cover__card">
        <span className="cover__photo" aria-hidden="true">
          <Image src={engagement} alt="" fill priority sizes="(max-width: 30rem) 100vw, 25rem" style={{ objectFit: "cover" }} />
        </span>

        <span className="cover__corner cover__corner--tl"><Corner corner="tl" /></span>
        <span className="cover__corner cover__corner--br"><Corner corner="br" /></span>

        <button
          type="button"
          className={`envelope-face ${envelopeOpen ? "envelope-face--open" : ""}`}
          onClick={() => setEnvelopeOpen(true)}
          aria-hidden={envelopeOpen}
          tabIndex={envelopeOpen ? -1 : 0}
          aria-label="Open the envelope"
        >
          <Image
            className="envelope-face__img envelope-face__img--closed"
            src={envelopeClosed}
            alt=""
            fill
            priority
            sizes="(max-width: 30rem) 100vw, 25rem"
            style={{ objectFit: "cover" }}
          />
          <Image
            className="envelope-face__img envelope-face__img--open"
            src={envelopeOpenImg}
            alt=""
            fill
            sizes="(max-width: 30rem) 100vw, 25rem"
            style={{ objectFit: "cover" }}
          />
          <span className="envelope-face__scrim" aria-hidden="true" />

          <span className="envelope-face__label">A Wedding Invitation</span>
          <span className="envelope-face__names">
            {couple.first} <em className="script">&amp;</em> {couple.second}
          </span>
          <span className="envelope-face__tap">Tap to open</span>
        </button>

        <div className={`cover__body ${envelopeOpen ? "cover__body--shown" : "cover__body--hidden"}`}>
          {/* the crowned crest frames the couple's own JM monogram, tinted sage */}
          <div className="crest crest--sage">
            <Image src={crest} alt="" priority sizes="(max-width: 30rem) 62vw, 15rem" />
            <Image
              className="crest__monogram"
              src={monogram}
              alt={`${couple.first} and ${couple.second}`}
              priority
              sizes="(max-width: 30rem) 22vw, 5.5rem"
            />
          </div>

          <p className="cover__eyebrow">The Wedding Of</p>

          <h1 className="cover__names">
            <span>{couple.first}</span>
            <em>&amp;</em>
            <span>{couple.second}</span>
          </h1>

          <p className="cover__date">
            {wedding.dateLabel.month} {wedding.dateLabel.day}, {wedding.dateLabel.year}
          </p>

          <button className="btn btn--quiet cover__open" type="button" onClick={open}>
            Open Invitation
          </button>
        </div>
      </div>

      <style jsx>{`
        .cover {
          position: fixed;
          inset: 0;
          z-index: 60;
          display: grid;
          place-items: center;
          padding: clamp(1.25rem, 5vw, 3rem);
          /* the same warm cream the rest of the page is set on */
          background:
            radial-gradient(115% 80% at 50% 6%, var(--gold-050), transparent 62%),
            linear-gradient(168deg, var(--ivory), var(--ivory-dim) 70%, var(--gold-200));
          transition: opacity 1s ease, transform 1s cubic-bezier(0.7, 0, 0.3, 1);
        }
        .cover--leaving {
          opacity: 0;
          transform: translateY(-4%) scale(1.04);
          pointer-events: none;
        }

        .cover__card {
          position: relative;
          width: min(100%, 25rem);
          min-height: 27rem;
          padding: clamp(2.5rem, 8vw, 3.5rem) clamp(1.5rem, 6vw, 2.5rem) clamp(2rem, 7vw, 3rem);
          border-radius: 26px;
          background: linear-gradient(180deg, #ffffff, var(--ivory));
          border: 1px solid var(--hair-soft);
          box-shadow: 0 40px 80px -30px rgba(63, 45, 32, 0.45);
          overflow: hidden;
          text-align: center;
          animation: rise 1.1s cubic-bezier(0.2, 0.7, 0.25, 1) both;
        }
        @keyframes rise {
          from { opacity: 0; transform: translateY(2.5rem) scale(0.96); }
          to   { opacity: 1; transform: none; }
        }

        /* the engagement photo, softened behind the letter — the envelope
           face (opaque) sits above it while closed, so it only reads once
           the flap has opened. */
        .cover__photo {
          position: absolute;
          inset: 0;
          z-index: 0;
          overflow: hidden;
        }
        .cover__photo :global(img) {
          filter: blur(9px) saturate(0.9);
          transform: scale(1.15);
        }
        .cover__photo::after {
          content: "";
          position: absolute;
          inset: 0;
          background: linear-gradient(
            180deg,
            rgba(248, 242, 230, 0.78),
            rgba(248, 242, 230, 0.86) 45%,
            rgba(248, 242, 230, 0.93) 100%
          );
        }

        /* ── the closed envelope, over the letter beneath ───────────────
           The two exact photos supplied: the closed envelope first, then a
           crossfade to the opened one, held for a beat, before the whole
           face lifts away and the letter slides up from underneath it. */
        .envelope-face {
          position: absolute;
          inset: 0;
          z-index: 5;
          display: block;
          border: 0;
          margin: 0;
          padding: 0;
          border-radius: inherit;
          background: var(--card);
          cursor: pointer;
          overflow: hidden;
          transition: opacity 0.6s ease 0.9s, transform 0.6s ease 0.9s;
        }
        .envelope-face--open {
          opacity: 0;
          transform: translateY(-4%);
          pointer-events: none;
        }

        /* next/image renders a plain <img> for a custom component, which
           styled-jsx never auto-scopes — these need :global() to bite. */
        :global(.envelope-face__img) {
          transition: opacity 0.7s ease;
        }
        :global(.envelope-face__img--closed) { opacity: 1; }
        :global(.envelope-face__img--open) { opacity: 0; }
        :global(.envelope-face--open .envelope-face__img--closed) { opacity: 0; }
        :global(.envelope-face--open .envelope-face__img--open) { opacity: 1; }

        .envelope-face__scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            180deg,
            rgba(38, 30, 20, 0.05) 0%,
            rgba(38, 30, 20, 0.02) 45%,
            rgba(38, 30, 20, 0.55) 100%
          );
        }

        .envelope-face__label {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 5.5rem;
          z-index: 2;
          font-family: var(--display);
          font-size: 0.8rem;
          letter-spacing: 0.22em;
          text-transform: uppercase;
          color: rgba(255, 255, 255, 0.85);
        }
        .envelope-face__names {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 3.4rem;
          z-index: 2;
          font-family: var(--display);
          font-size: 1.4rem;
          color: #fff;
        }
        .envelope-face__names em { font-size: 0.85em; }
        .envelope-face__tap {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 1.6rem;
          z-index: 2;
          font-size: 0.78rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: rgba(255, 255, 255, 0.85);
          animation: tap-pulse 1.8s ease-in-out infinite;
        }
        @keyframes tap-pulse {
          0%, 100% { opacity: 0.55; }
          50% { opacity: 1; }
        }

        .cover__body--hidden { opacity: 0; transform: translateY(1.25rem); }
        .cover__body--shown {
          opacity: 1;
          transform: translateY(0);
          transition: opacity 0.7s ease 0.95s, transform 0.7s ease 0.95s;
        }

        @media (prefers-reduced-motion: reduce) {
          .envelope-face, .envelope-face__img, .envelope-face__tap, .cover__body--shown { animation: none; transition: opacity 0.2s linear; }
        }

        .crest {
          position: relative;
          width: min(62%, 15rem);
          margin-bottom: -0.35rem;
          animation: crest-in 1.3s cubic-bezier(0.2, 0.7, 0.25, 1) both 0.25s;
        }
        .crest :global(img) { width: 100%; height: auto; display: block; }

        /* the crest ships gold — shift its hue to the sage swatch supplied */
        .crest--sage > :global(img:first-child) {
          filter: hue-rotate(72deg) saturate(0.55) brightness(1.12);
        }

        /* sized to sit inside the oval's pearled inner ring */
        .crest :global(img.crest__monogram) {
          position: absolute;
          top: 46.5%;
          left: 50%;
          transform: translate(-50%, -50%);
          width: 37%;
          height: auto;
        }

        @keyframes crest-in {
          from { opacity: 0; transform: translateY(1rem) scale(0.94); }
          to   { opacity: 1; transform: none; }
        }

        .cover__corner {
          position: absolute;
          opacity: 0.85;
          pointer-events: none;
        }
        .cover__corner--tl { top: 0.5rem; left: 0.5rem; }
        .cover__corner--br { right: 0.5rem; bottom: 0.5rem; }

        .cover__body {
          position: relative;
          z-index: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 1.15rem;
          padding-top: 1rem;
        }

        .cover__eyebrow {
          font-family: var(--display);
          font-size: 0.8rem;
          letter-spacing: 0.28em;
          text-transform: uppercase;
          color: var(--ink-faint);
          margin: 0;
        }

        .cover__names {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0;
          font-family: var(--font-script), "Pinyon Script", cursive;
          font-size: clamp(2.6rem, 12vw, 3.6rem);
          line-height: 1.15;
          color: var(--gold-700);
        }
        .cover__names em {
          font-size: 0.55em;
          font-style: normal;
          line-height: 1;
          margin: 0.1em 0;
        }

        .cover__date {
          font-family: var(--display);
          font-size: 1.1rem;
          letter-spacing: 0.08em;
          color: var(--ink-soft);
        }

        .cover__open {
          margin-top: 0.5rem;
          border-radius: 4px;
          letter-spacing: 0.22em;
        }

        @media (prefers-reduced-motion: reduce) {
          .cover, .cover__card, .crest { animation: none; transition: opacity 0.2s linear; }
        }
      `}</style>
    </div>
  );
}
