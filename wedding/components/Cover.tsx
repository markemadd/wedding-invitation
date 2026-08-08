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

        <div className="cover__body">
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
