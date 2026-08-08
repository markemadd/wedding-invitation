"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { couple, wedding } from "@/lib/config";
import crest from "@/public/crest.png";
import monogram from "@/public/monogram.png";
import { Corner, Divider } from "./Ornaments";

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
          <span className="envelope-face__flap" aria-hidden="true" />
          <span className="envelope-face__seal" aria-hidden="true">
            <Image src={monogram} alt="" sizes="3rem" />
          </span>
          <span className="envelope-face__label">A Wedding Invitation</span>
          <span className="envelope-face__names">
            {couple.first} <em className="script">&amp;</em> {couple.second}
          </span>
          <span className="envelope-face__tap">Tap to open</span>
        </button>

        <div className={`cover__body ${envelopeOpen ? "cover__body--shown" : "cover__body--hidden"}`}>
          {/* the crowned crest frames the couple's own JM monogram */}
          <div className="crest">
            <Image src={crest} alt="" priority sizes="(max-width: 30rem) 62vw, 15rem" />
            <Image
              className="crest__monogram"
              src={monogram}
              alt={`${couple.first} and ${couple.second}`}
              priority
              sizes="(max-width: 30rem) 22vw, 5.5rem"
            />
          </div>

          <h1 className="cover__names">
            <span>{couple.first.toUpperCase()}</span>
            <em className="script">&amp;</em>
            <span>{couple.second.toUpperCase()}</span>
          </h1>

          <Divider width={150} />

          <p className="cover__date">
            {wedding.dateLabel.month} {wedding.dateLabel.day}, {wedding.dateLabel.year}
          </p>
          <p className="cover__invited">You&rsquo;re Invited</p>

          <button className="btn" type="button" onClick={open}>
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
          /* the deep sage the couple's monogram is set against */
          background:
            radial-gradient(115% 80% at 50% 6%, #5E7A52, transparent 62%),
            linear-gradient(168deg, #4A6141, #33452F 70%, #26341F);
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
          box-shadow: 0 40px 80px -30px rgba(16, 26, 12, 0.62);
          overflow: hidden;
          text-align: center;
          animation: rise 1.1s cubic-bezier(0.2, 0.7, 0.25, 1) both;
        }
        @keyframes rise {
          from { opacity: 0; transform: translateY(2.5rem) scale(0.96); }
          to   { opacity: 1; transform: none; }
        }

        /* ── the closed envelope, over the letter beneath ─────────────── */
        .envelope-face {
          position: absolute;
          inset: 0;
          z-index: 5;
          display: block;
          border: 0;
          margin: 0;
          padding: 0;
          border-radius: inherit;
          background: linear-gradient(180deg, #ffffff, var(--ivory));
          cursor: pointer;
          perspective: 1000px;
          transition: opacity 0.5s ease 0.55s, transform 0.5s ease 0.55s;
        }
        .envelope-face--open {
          opacity: 0;
          transform: translateY(-4%);
          pointer-events: none;
        }

        .envelope-face__flap {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 56%;
          clip-path: polygon(0 0, 100% 0, 50% 100%);
          background: linear-gradient(155deg, #ffffff, var(--ivory) 75%);
          box-shadow: 0 10px 16px -12px rgba(20, 30, 15, 0.4);
          transform-origin: top center;
          transform: rotateX(0deg);
          transition: transform 0.85s cubic-bezier(0.6, 0, 0.25, 1);
        }
        .envelope-face--open .envelope-face__flap {
          transform: rotateX(-120deg);
        }

        .envelope-face__seal {
          position: absolute;
          top: 54%;
          left: 50%;
          transform: translate(-50%, -50%);
          z-index: 1;
          width: 3.4rem;
          height: 3.4rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--gold-700);
          box-shadow: 0 4px 10px rgba(0, 0, 0, 0.35), inset 0 -3px 6px rgba(0, 0, 0, 0.25);
        }
        .envelope-face__seal :global(img) {
          width: 60%;
          height: auto;
          filter: brightness(0) invert(1);
          opacity: 0.92;
        }

        .envelope-face__label {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 5.5rem;
          font-family: var(--display);
          font-size: 0.8rem;
          letter-spacing: 0.22em;
          text-transform: uppercase;
          color: var(--ink-faint);
        }
        .envelope-face__names {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 3.4rem;
          font-family: var(--display);
          font-size: 1.4rem;
          color: var(--gold-700);
        }
        .envelope-face__names em { font-size: 0.85em; }
        .envelope-face__tap {
          position: absolute;
          left: 0;
          right: 0;
          bottom: 1.6rem;
          font-size: 0.78rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--ink-soft);
          animation: tap-pulse 1.8s ease-in-out infinite;
        }
        @keyframes tap-pulse {
          0%, 100% { opacity: 0.55; }
          50% { opacity: 1; }
        }

        .cover__body--hidden { opacity: 0; }
        .cover__body--shown {
          opacity: 1;
          transition: opacity 0.6s ease 0.7s;
        }

        @media (prefers-reduced-motion: reduce) {
          .envelope-face, .envelope-face__flap, .envelope-face__tap { animation: none; transition: opacity 0.2s linear; }
          .envelope-face--open .envelope-face__flap { transform: none; }
        }

        .crest {
          position: relative;
          width: min(62%, 15rem);
          margin-bottom: -0.35rem;
          animation: crest-in 1.3s cubic-bezier(0.2, 0.7, 0.25, 1) both 0.25s;
        }
        .crest :global(img) { width: 100%; height: auto; display: block; }

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
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 1.15rem;
          padding-top: 1rem;
        }

        .cover__names {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.2rem;
          font-size: clamp(2.1rem, 9vw, 2.9rem);
          letter-spacing: 0.08em;
          color: var(--gold-700);
        }
        .cover__names em {
          font-size: 0.62em;
          letter-spacing: 0;
          font-weight: 400;
        }

        .cover__date {
          font-family: var(--display);
          font-size: 1.3rem;
          color: var(--ink);
        }
        .cover__invited {
          font-family: var(--display);
          font-size: 1.2rem;
          color: var(--ink-soft);
        }

        @media (prefers-reduced-motion: reduce) {
          .cover, .cover__card, .crest { animation: none; transition: opacity 0.2s linear; }
        }
      `}</style>
    </div>
  );
}
