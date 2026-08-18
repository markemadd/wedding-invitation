"use client";

import { useEffect, useRef, useState } from "react";

/**
 * The gate. Covers the page on load; "Open Invitation" lifts it away and
 * releases the scroll — the same beat as the reference template.
 *
 * The reveal itself is a supplied video (envelope opening → the couple's
 * names and date on the letter) rather than a built cover — once it ends,
 * the same "Open Invitation" button appears over its last frame.
 */
export default function Cover({ onOpen }: { onOpen: () => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [videoEnded, setVideoEnded] = useState(false);
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
        <span className="cover__video-wrap">
          {/* a blurred, cropped copy fills the edges on tall phone screens —
              the real (uncropped) video sits centered on top of it, so the
              baked-in text is never cut off the way a single cover-fit
              video would be against a 16:9 clip */}
          <video
            className="cover__video cover__video--bg"
            src="/envelope-video.mp4"
            aria-hidden="true"
            autoPlay
            muted
            playsInline
            preload="auto"
          />

          {/* locked to the video's own 16:9 shape and centered in the wrap,
              so the button below stays pinned to the real frame edge
              instead of drifting on screens the video can't cover cleanly */}
          <span className="cover__frame">
            <video
              ref={videoRef}
              className="cover__video cover__video--fg"
              src="/envelope-video.mp4"
              autoPlay
              muted
              playsInline
              preload="auto"
              onEnded={() => setVideoEnded(true)}
            />

            <button
              type="button"
              className={`btn btn--quiet cover__open ${videoEnded ? "cover__open--shown" : "cover__open--hidden"}`}
              onClick={open}
              aria-hidden={!videoEnded}
              tabIndex={videoEnded ? 0 : -1}
            >
              Open Invitation
            </button>
          </span>
        </span>
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
          width: min(94vw, 34rem);
          border-radius: 26px;
          box-shadow: 0 40px 80px -30px rgba(63, 45, 32, 0.45);
          overflow: hidden;
          text-align: center;
          animation: rise 1.1s cubic-bezier(0.2, 0.7, 0.25, 1) both;
        }
        @keyframes rise {
          from { opacity: 0; transform: translateY(2.5rem) scale(0.96); }
          to   { opacity: 1; transform: none; }
        }

        /* the card takes the video's own shape, so nothing is cropped and
           no white strip is needed beneath it for the button */
        .cover__video-wrap {
          position: relative;
          display: block;
          width: 100%;
          aspect-ratio: 16 / 9;
        }
        .cover__video {
          position: absolute;
          inset: 0;
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        .cover__video--bg {
          z-index: 0;
          filter: blur(22px) saturate(1.05) brightness(0.95);
          transform: scale(1.15);
        }

        /* on the card, this is just the wrap's own box (already 16:9); the
           mobile breakpoint below re-sizes it to the video's real rendered
           edges inside the full-bleed screen, so the button anchored to it
           never drifts off the actual frame */
        .cover__frame {
          position: absolute;
          inset: 0;
        }
        .cover__video--fg {
          z-index: 1;
        }

        /* sits over the clear ground beneath the baked-in date */
        .cover__open {
          position: absolute;
          left: 50%;
          bottom: 6.5%;
          transform: translate(-50%, 0.5rem);
          border-radius: 4px;
          padding: 0 1.3rem;
          min-height: 2.5rem;
          font-size: 0.8rem;
          letter-spacing: 0.2em;
          background: rgba(248, 242, 230, 0.9);
          backdrop-filter: blur(2px);
          box-shadow: 0 6px 16px -6px rgba(38, 30, 20, 0.35);
          opacity: 0;
          transition: opacity 0.6s ease 0.15s, transform 0.6s ease 0.15s;
        }
        .cover__open--hidden { pointer-events: none; }
        .cover__open--shown {
          opacity: 1;
          transform: translate(-50%, 0);
        }

        @media (prefers-reduced-motion: reduce) {
          .cover, .cover__card, .cover__open { animation: none; transition: opacity 0.2s linear; }
        }

        /* on phones, drop the card entirely — the video fills the screen */
        @media (max-width: 30rem) {
          .cover { padding: 0; }
          .cover__card {
            width: 100vw;
            height: 100dvh;
            border-radius: 0;
            box-shadow: none;
          }
          .cover__video-wrap {
            height: 100%;
            aspect-ratio: auto;
          }
          /* the wrap now equals the viewport, so this pure-CSS "contain"
             formula sizes the frame to the video's true rendered box */
          .cover__frame {
            inset: auto;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: min(100vw, calc(100dvh * 16 / 9));
            height: min(100dvh, calc(100vw * 9 / 16));
          }
          /* feathers the sharp video's edge into the blurred fill behind
             it, instead of a hard rectangle floating over soft blur — kept
             off the button (a sibling) so it never fades with it */
          .cover__video--fg {
            mask-image: radial-gradient(ellipse 78% 78% at 50% 50%, #000 65%, transparent 100%);
            -webkit-mask-image: radial-gradient(ellipse 78% 78% at 50% 50%, #000 65%, transparent 100%);
          }
        }
      `}</style>
    </div>
  );
}
