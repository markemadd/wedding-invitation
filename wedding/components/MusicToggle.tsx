"use client";

import { useEffect, useRef, useState } from "react";

/**
 * The floating audio button from the reference template. Renders nothing
 * unless a track is configured, and never autoplays without the cover being
 * opened first (browsers block it, and it's rude besides).
 */
export default function MusicToggle({ src, armed }: { src: string; armed: boolean }) {
  const audio = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!armed || !src || !audio.current) return;
    audio.current.volume = 0.35;
    audio.current
      .play()
      .then(() => setPlaying(true))
      .catch(() => setPlaying(false)); // autoplay refused — the button still works
  }, [armed, src]);

  /* Stop the moment the page goes away.
     Closing a tab (or backgrounding Safari on iOS) does not reliably fire
     "unload", and a page kept in the back/forward cache goes on playing —
     so pause on pagehide AND on the visibility change that precedes it. */
  useEffect(() => {
    if (!src) return;

    const stop = () => {
      const el = audio.current;
      if (el && !el.paused) {
        el.pause();
        setPlaying(false);
      }
    };
    const onVisibility = () => {
      if (document.visibilityState === "hidden") stop();
    };

    window.addEventListener("pagehide", stop);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.removeEventListener("pagehide", stop);
      document.removeEventListener("visibilitychange", onVisibility);
      stop(); // unmounting the player must silence it too
    };
  }, [src]);

  if (!src) return null;

  function toggle() {
    const el = audio.current;
    if (!el) return;
    if (el.paused) {
      el.play().then(() => setPlaying(true)).catch(() => setPlaying(false));
    } else {
      el.pause();
      setPlaying(false);
    }
  }

  return (
    <>
      <audio ref={audio} src={src} loop preload="none" />
      <button
        className="music"
        type="button"
        onClick={toggle}
        aria-pressed={playing}
        aria-label={playing ? "Pause music" : "Play music"}
      >
        <span className={`music__bars ${playing ? "is-playing" : ""}`} aria-hidden="true">
          <i /><i /><i />
        </span>
      </button>
    </>
  );
}
