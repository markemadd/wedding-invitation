"use client";

import { useEffect, useState } from "react";
import { weddingDate } from "@/lib/config";
import Reveal from "./Reveal";

function timeLeft() {
  const diff = Math.max(0, weddingDate.getTime() - Date.now());
  const day = 24 * 3600 * 1000;
  const hour = 3600 * 1000;
  const minute = 60 * 1000;
  return {
    days: Math.floor(diff / day),
    hours: Math.floor((diff % day) / hour),
    minutes: Math.floor((diff % hour) / minute),
    seconds: Math.floor((diff % minute) / 1000),
  };
}

/** Ticks down to the ceremony. Mounts blank server-side, fills in on the client so the count is never stale from a cached page. */
export default function Countdown() {
  const [left, setLeft] = useState<ReturnType<typeof timeLeft> | null>(null);

  useEffect(() => {
    setLeft(timeLeft());
    const id = setInterval(() => setLeft(timeLeft()), 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <Reveal className="section">
      <p className="eyebrow eyebrow-rule">Counting Down</p>
      <div className="datestrip" aria-live="off">
        <span><strong>{left ? left.days : "–"}</strong>Days</span>
        <i />
        <span><strong>{left ? left.hours : "–"}</strong>Hours</span>
        <i />
        <span><strong>{left ? left.minutes : "–"}</strong>Min</span>
        <i />
        <span><strong>{left ? left.seconds : "–"}</strong>Sec</span>
      </div>
    </Reveal>
  );
}
