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
          {/* the letter card, peeking out above the pocket */}
          <span className="envelope-face__peek" aria-hidden="true" />

          <span className="envelope-face__pocket" aria-hidden="true">
            <span className="envelope-face__flap" />
            <span className="envelope-face__crease envelope-face__crease--l" />
            <span className="envelope-face__crease envelope-face__crease--r" />
          </span>

          <span className="envelope-face__ribbon" aria-hidden="true">
            <span className="envelope-face__tail envelope-face__tail--l" />
            <span className="envelope-face__tail envelope-face__tail--r" />
            <span className="envelope-face__bow envelope-face__bow--l" />
            <span className="envelope-face__bow envelope-face__bow--r" />
          </span>

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

        /* ── the closed envelope, over the letter beneath ───────────────
           A peeking card, a folded ivory pocket, a satin ribbon tied in a
           bow, and a wax seal — built from gradients and clip-paths, not a
           photo, so it stays crisp at any size and costs nothing to load. */
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
          perspective: 1200px;
          transition: opacity 0.5s ease 0.6s, transform 0.5s ease 0.6s;
        }
        .envelope-face--open {
          opacity: 0;
          transform: translateY(-4%);
          pointer-events: none;
        }

        /* the letter, sticking up out of the envelope */
        .envelope-face__peek {
          position: absolute;
          top: 4%;
          left: 21%;
          right: 21%;
          height: 30%;
          border-radius: 6px 6px 0 0;
          background: linear-gradient(180deg, #ffffff, var(--card));
          box-shadow: 0 -1px 0 rgba(63, 45, 32, 0.08) inset, 0 4px 10px -6px rgba(63, 45, 32, 0.35);
        }

        /* the envelope body */
        .envelope-face__pocket {
          position: absolute;
          top: 16%;
          left: 0;
          right: 0;
          bottom: 0;
          overflow: hidden;
          background: linear-gradient(175deg, #ffffff, var(--ivory) 60%);
          box-shadow: 0 -6px 14px -10px rgba(63, 45, 32, 0.3) inset;
        }
        .envelope-face__flap {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 62%;
          clip-path: polygon(0 0, 100% 0, 50% 100%);
          background: linear-gradient(155deg, #ffffff, var(--gold-050) 80%);
          box-shadow: 0 10px 16px -12px rgba(63, 45, 32, 0.35);
          transform-origin: top center;
          transform: rotateX(0deg);
          transition: transform 0.85s cubic-bezier(0.6, 0, 0.25, 1);
        }
        .envelope-face--open .envelope-face__flap {
          transform: rotateX(-120deg);
        }
        /* the folded side flaps, hinted at as creases behind the ribbon */
        .envelope-face__crease {
          position: absolute;
          bottom: -6%;
          width: 75%;
          height: 60%;
          border-top: 1px solid var(--hair-soft);
          opacity: 0.8;
        }
        .envelope-face__crease--l { left: -18%; transform: rotate(24deg); transform-origin: top left; }
        .envelope-face__crease--r { right: -18%; transform: rotate(-24deg); transform-origin: top right; }

        /* the satin ribbon, tied across the middle */
        .envelope-face__ribbon {
          position: absolute;
          left: -6%;
          right: -6%;
          top: 53%;
          height: 2.3rem;
          transform: translateY(-50%) rotate(-1.5deg);
          background: linear-gradient(180deg, var(--gold-200) 0%, #fff 12%, var(--gold-050) 50%, #fff 88%, var(--gold-200) 100%);
          box-shadow: 0 6px 14px -8px rgba(63, 45, 32, 0.4);
        }
        .envelope-face__tail {
          position: absolute;
          top: 100%;
          width: 1.15rem;
          height: 3.4rem;
          background: linear-gradient(180deg, var(--gold-200), var(--gold-050) 60%, #fff);
          box-shadow: 0 4px 8px -4px rgba(63, 45, 32, 0.35);
        }
        .envelope-face__tail--l {
          left: 46.5%;
          transform-origin: top center;
          transform: rotate(16deg);
          clip-path: polygon(0 0, 100% 0, 100% 82%, 50% 100%, 0 82%);
        }
        .envelope-face__tail--r {
          right: 46.5%;
          transform-origin: top center;
          transform: rotate(-16deg);
          clip-path: polygon(0 0, 100% 0, 100% 82%, 50% 100%, 0 82%);
        }
        .envelope-face__bow {
          position: absolute;
          top: 50%;
          width: 3rem;
          height: 2.3rem;
          background: linear-gradient(155deg, #fff, var(--gold-200) 55%, var(--gold-400) 100%);
          box-shadow: 0 5px 12px -5px rgba(63, 45, 32, 0.5), inset 0 1px 1px rgba(255, 255, 255, 0.6);
        }
        .envelope-face__bow--l {
          left: calc(50% - 2.85rem);
          transform: translateY(-50%) rotate(6deg);
          clip-path: polygon(100% 6%, 0 0, 18% 50%, 0 100%, 100% 94%, 46% 50%);
        }
        .envelope-face__bow--r {
          right: calc(50% - 2.85rem);
          transform: translateY(-50%) rotate(-6deg);
          clip-path: polygon(0 6%, 100% 0, 82% 50%, 100% 100%, 0 94%, 54% 50%);
        }

        .envelope-face__seal {
          position: absolute;
          top: 53%;
          left: 50%;
          transform: translate(-50%, -50%);
          z-index: 1;
          width: 3.4rem;
          height: 3.4rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: radial-gradient(circle at 35% 30%, var(--gold-600), var(--gold-800) 75%);
          box-shadow: 0 4px 10px rgba(63, 45, 32, 0.45), inset 0 -3px 6px rgba(0, 0, 0, 0.25), inset 0 2px 3px rgba(255, 255, 255, 0.35);
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
          z-index: 2;
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
          z-index: 2;
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
          z-index: 2;
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
