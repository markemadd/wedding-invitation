"use client";

import { useEffect, useRef, useState } from "react";

const VIDEO_FALLBACK_MS = 10500; // clip is ~9.5s — a safety net in case "ended" never fires

/**
 * The gate. Covers the page on load; "Open Invitation" lifts it away and
 * releases the scroll.
 *
 * The reveal is a supplied portrait video (envelope opening → the couple's
 * names and date on the letter). It fills the screen edge to edge — once it
 * ends, "Open Invitation" fades in over its last frame. A timer backs up the
 * video's own "ended" event, which some mobile browsers can skip.
 */
export default function Cover({ onOpen }: { onOpen: () => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [videoEnded, setVideoEnded] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [gone, setGone] = useState(false);

  useEffect(() => {
    document.body.style.overflow = "hidden";
    const fallback = window.setTimeout(() => setVideoEnded(true), VIDEO_FALLBACK_MS);
    return () => {
      document.body.style.overflow = "";
      window.clearTimeout(fallback);
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
      <video
        ref={videoRef}
        className="cover__video"
        src="/envelope-video.mp4"
        autoPlay
        muted
        playsInline
        preload="auto"
        onEnded={() => setVideoEnded(true)}
        onError={() => setVideoEnded(true)}
      />

      <button
        type="button"
        className={`btn btn--quiet cover__open ${videoEnded ? "cover__open--shown" : "cover__open--hidden"}`}
        onClick={open}
        aria-hidden={!videoEnded}
        tabIndex={videoEnded ? 0 : -1}
      >
        Continue to Invitation
      </button>

      <style jsx>{`
        .cover {
          position: fixed;
          inset: 0;
          z-index: 60;
          background: #eee7d8;
          transition: opacity 1s ease, transform 1s cubic-bezier(0.7, 0, 0.3, 1);
        }
        .cover--leaving {
          opacity: 0;
          transform: translateY(-4%) scale(1.04);
          pointer-events: none;
        }

        .cover__video {
          position: absolute;
          inset: 0;
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        /* the clear ground between the names and the date, baked into the clip */
        .cover__open {
          position: absolute;
          left: 50%;
          bottom: 32%;
          transform: translate(-50%, 0.5rem);
          border-radius: 4px;
          padding: 0 1.4rem;
          min-height: 2.75rem;
          font-size: 0.8rem;
          letter-spacing: 0.16em;
          background: rgba(248, 242, 230, 0.92);
          box-shadow: 0 6px 16px -6px rgba(38, 30, 20, 0.4);
          opacity: 0;
          transition: opacity 0.6s ease 0.15s, transform 0.6s ease 0.15s;
        }
        .cover__open--hidden { pointer-events: none; }
        .cover__open--shown {
          opacity: 1;
          transform: translate(-50%, 0);
        }

        @media (prefers-reduced-motion: reduce) {
          .cover, .cover__open { transition: opacity 0.2s linear; }
        }
      `}</style>
    </div>
  );
}
