"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { couple } from "@/lib/config";
import landingBg from "@/public/landing-bg.png";
import landingEnvelope from "@/public/landing-envelope.png";
import landingSeal from "@/public/landing-seal.png";
import landingSprig from "@/public/landing-sprig.png";

/**
 * The gate. Covers the page on load; opening the envelope lifts it away and
 * releases the scroll — the same painted-landscape, lace-envelope layout as
 * the couple's Canva site, rebuilt here with the same image assets.
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
      <Image className="cover__bg" src={landingBg} alt="" fill priority sizes="100vw" style={{ objectFit: "cover" }} />
      <span className="cover__scrim" aria-hidden="true" />

      <div className="cover__content">
        <p className="cover__eyebrow">We&rsquo;re Getting Married</p>
        <h1 className="cover__names">
          {couple.first} <em>&amp;</em> {couple.second}
        </h1>

        <button type="button" className="cover__envelope" onClick={open} aria-label="Open the invitation">
          <Image src={landingEnvelope} alt="" priority sizes="(max-width: 30rem) 82vw, 24rem" />
          <span className="cover__monogram">{couple.first[0]}</span>
          <Image className="cover__seal" src={landingSeal} alt="" sizes="4.5rem" />
          <Image className="cover__sprig" src={landingSprig} alt="" sizes="7rem" />
        </button>

        <button type="button" className="cover__open" onClick={open}>
          Open Invitation
        </button>
      </div>

      <style jsx>{`
        .cover {
          position: fixed;
          inset: 0;
          z-index: 60;
          overflow: hidden;
          background: #cdc9b8;
          transition: opacity 1s ease, transform 1s cubic-bezier(0.7, 0, 0.3, 1);
        }
        .cover--leaving {
          opacity: 0;
          transform: translateY(-4%) scale(1.04);
          pointer-events: none;
        }

        :global(.cover__bg) { z-index: 0; }
        .cover__scrim {
          position: absolute;
          inset: 0;
          z-index: 1;
          background: linear-gradient(
            180deg,
            rgba(255, 255, 255, 0.35) 0%,
            rgba(255, 255, 255, 0.12) 30%,
            rgba(255, 255, 255, 0.12) 60%,
            rgba(255, 255, 255, 0.4) 100%
          );
        }

        .cover__content {
          position: relative;
          z-index: 2;
          height: 100%;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 1.5rem;
          padding: 2rem 1.5rem;
          text-align: center;
        }

        .cover__eyebrow {
          margin: 0;
          font-family: var(--display);
          font-size: 0.85rem;
          letter-spacing: 0.24em;
          text-transform: uppercase;
          color: var(--ink-soft);
        }

        .cover__names {
          margin: 0;
          font-family: var(--font-script), "Pinyon Script", cursive;
          font-size: clamp(2.4rem, 11vw, 3.4rem);
          line-height: 1.1;
          color: #3a4a52;
        }
        .cover__names em { font-style: normal; }

        .cover__envelope {
          position: relative;
          display: block;
          width: min(82vw, 24rem);
          border: 0;
          padding: 0;
          background: none;
          cursor: pointer;
        }
        .cover__envelope :global(img) {
          width: 100%;
          height: auto;
          display: block;
        }

        .cover__monogram {
          position: absolute;
          top: 22%;
          left: 50%;
          transform: translate(-50%, -50%);
          font-family: var(--font-script), "Pinyon Script", cursive;
          font-size: 1.6rem;
          color: rgba(255, 255, 255, 0.92);
        }

        /* next/image renders a plain <img> for a custom component, which
           styled-jsx never auto-scopes — these need :global() to bite */
        :global(.cover__seal) {
          position: absolute !important;
          top: 46%;
          left: 50%;
          transform: translate(-50%, -50%);
          width: 3.6rem !important;
          height: auto !important;
          filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.35));
        }

        :global(.cover__sprig) {
          position: absolute !important;
          left: -8%;
          bottom: -10%;
          width: 7.5rem !important;
          height: auto !important;
          transform: rotate(-8deg);
        }

        .cover__open {
          border: 0;
          background: none;
          padding: 0.4rem 0;
          font-family: var(--display);
          font-size: 0.85rem;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: #3a4a52;
          border-bottom: 1px solid rgba(58, 74, 82, 0.4);
          cursor: pointer;
        }

        @media (prefers-reduced-motion: reduce) {
          .cover { transition: opacity 0.2s linear; }
        }
      `}</style>
    </div>
  );
}
