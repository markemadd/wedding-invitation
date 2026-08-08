"use client";

import Image, { type StaticImageData } from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import { wedding } from "@/lib/config";
import p1 from "@/public/story/01.webp";
import p2 from "@/public/story/02.webp";
import p3 from "@/public/story/03.webp";
import p4 from "@/public/story/04.webp";
import p5 from "@/public/story/05.webp";
import Reveal from "./Reveal";

const PHOTOS: StaticImageData[] = [p1, p2, p3, p4, p5];

/**
 * The engagement photographs.
 *
 * Scroll-snap does the carousel work — the track is a real scroller, so swipe
 * on a phone and trackpad flicks come free and keep their native feel. The
 * arrows and dots drive the same scroller rather than a parallel index, so the
 * controls and the swipe can never disagree about which photo is showing.
 */
export default function Story() {
  const track = useRef<HTMLUListElement | null>(null);
  const [index, setIndex] = useState(0);

  /* read the active slide back out of the scroller */
  const sync = useCallback(() => {
    const el = track.current;
    if (!el) return;
    const middle = el.scrollLeft + el.clientWidth / 2;
    let closest = 0;
    let best = Infinity;
    Array.from(el.children).forEach((child, i) => {
      const slide = child as HTMLElement;
      const centre = slide.offsetLeft + slide.offsetWidth / 2;
      const gap = Math.abs(centre - middle);
      if (gap < best) {
        best = gap;
        closest = i;
      }
    });
    setIndex(closest);
  }, []);

  useEffect(() => {
    const el = track.current;
    if (!el) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(sync);
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      cancelAnimationFrame(frame);
    };
  }, [sync]);

  function go(to: number) {
    const el = track.current;
    if (!el) return;
    const target = el.children[Math.max(0, Math.min(PHOTOS.length - 1, to))] as HTMLElement;
    if (!target) return;
    el.scrollTo({
      left: target.offsetLeft - (el.clientWidth - target.offsetWidth) / 2,
      behavior: "smooth",
    });
  }

  return (
    <Reveal className="section section--wide">
      <p className="eyebrow eyebrow-rule">Our Story</p>

      <div className="carousel">
        <ul className="carousel__track" ref={track} tabIndex={0}
            aria-label="Engagement photographs">
          {PHOTOS.map((photo, i) => (
            <li className="carousel__slide" key={i}>
              <Image
                src={photo}
                alt={`${wedding.groom} and ${wedding.bride}, photograph ${i + 1} of ${PHOTOS.length}`}
                sizes="(max-width: 40rem) 78vw, 26rem"
                placeholder="blur"
                priority={i === 0}
              />
            </li>
          ))}
        </ul>

        <button
          className="carousel__arrow carousel__arrow--prev"
          type="button"
          onClick={() => go(index - 1)}
          disabled={index === 0}
          aria-label="Previous photograph"
        >
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <path d="M15 4 7 12l8 8" fill="none" stroke="currentColor" strokeWidth="1.6"
                  strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>

        <button
          className="carousel__arrow carousel__arrow--next"
          type="button"
          onClick={() => go(index + 1)}
          disabled={index === PHOTOS.length - 1}
          aria-label="Next photograph"
        >
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <path d="M9 4l8 8-8 8" fill="none" stroke="currentColor" strokeWidth="1.6"
                  strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>

      <div className="carousel__dots" role="tablist" aria-label="Choose a photograph">
        {PHOTOS.map((_, i) => (
          <button
            key={i}
            type="button"
            role="tab"
            aria-selected={i === index}
            aria-label={`Photograph ${i + 1}`}
            className={i === index ? "is-current" : undefined}
            onClick={() => go(i)}
          />
        ))}
      </div>
    </Reveal>
  );
}
