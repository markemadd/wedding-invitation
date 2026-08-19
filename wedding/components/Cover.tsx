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
          <span className="cover__monogram">
            {couple.first[0]}
            {couple.second[0]}
          </span>
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
          top: 26%;
          left: 50%;
          transform: translate(-50%, -50%);
          font-family: var(--font-script), "Pinyon Script", cursive;
          font-size: 1.75rem;
          letter-spacing: 0.04em;
          color: rgba(255, 255, 255, 0.92);
        }

        /* next/image renders a plain <img> for a custom component, which
           styled-jsx never auto-scopes — these need :global() to bite.
           The image is cropped to the envelope itself (no transparent
           padding), so these percentages land on the artwork: the lace V
           meets at 50.2% / 70%, and the seal straddles that junction. */
        :global(.cover__seal) {
          position: absolute !important;
          top: 67%;
          left: 50.2%;
          transform: translate(-50%, -50%);
          width: 3.6rem !important;
          height: auto !important;
          filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.35));
        }

        /* tucked against the envelope's left edge, half on the paper and
           half on the landscape, as in the reference */
        :global(.cover__sprig) {
          position: absolute !important;
          left: -11%;
          top: 16%;
          width: 3.6rem !important;
          height: auto !important;
          transform: rotate(-10deg);
        }

        /* the painted background is pale and busy here, so the label gets a
           tinted plate of its own rather than sitting bare on the sky */
        .cover__open {
          border: 1px solid rgba(28, 42, 36, 0.25);
          border-radius: 2px;
          background: rgba(248, 244, 234, 0.82);
          backdrop-filter: blur(3px);
          padding: 0.7rem 1.6rem;
          font-family: var(--display);
          font-size: 0.85rem;
          font-weight: 600;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          color: #26342a;
          cursor: pointer;
          transition: background 0.25s ease, color 0.25s ease;
        }
        .cover__open:hover {
          background: #26342a;
          color: var(--ivory);
        }

        @media (prefers-reduced-motion: reduce) {
          .cover { transition: opacity 0.2s linear; }
        }
      `}</style>
    </div>
  );
}
