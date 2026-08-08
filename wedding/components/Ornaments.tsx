/**
 * Drawn botanicals. The reference template uses watercolour PNGs; these are
 * vector stand-ins that scale cleanly and cost nothing to load. Swap any of
 * them for artwork by dropping a file in /public and replacing the component.
 */

export function Divider({ width = 190 }: { width?: number }) {
  return (
    <svg className="sprig" width={width} height={26} viewBox="0 0 190 26" aria-hidden="true">
      <path d="M8 13h58" />
      <path d="M124 13h58" />
      <path d="M95 4c-7 4-11 6-11 9s4 5 11 9c7-4 11-6 11-9s-4-5-11-9z" className="petal" />
      <circle cx="95" cy="13" r="2.4" className="heart-dot" />
      <path d="M72 13c3-4 6-4 9 0-3 4-6 4-9 0z" className="leaf" />
      <path d="M109 13c3-4 6-4 9 0-3 4-6 4-9 0z" className="leaf" />
    </svg>
  );
}

export function Sprig({ flip = false }: { flip?: boolean }) {
  return (
    <svg
      className="sprig"
      width={54}
      height={130}
      viewBox="0 0 54 130"
      aria-hidden="true"
      style={flip ? { transform: "scaleX(-1)" } : undefined}
    >
      <path d="M27 126C27 96 25 62 30 32c2-12 6-20 10-26" />
      {[34, 52, 70, 88, 106].map((y, i) => (
        <g key={y}>
          <path d={`M27 ${y}c-9-3-14-9-15-16 9 1 14 6 15 16z`} className="leaf" />
          <path d={`M28 ${y - 9}c9-4 14-10 15-17-9 1-14 7-15 17z`} className="leaf" />
        </g>
      ))}
      <circle cx="40" cy="8" r="4.5" className="petal" />
      <circle cx="40" cy="8" r="1.6" className="heart-dot" />
    </svg>
  );
}

/** The floral corner tucked into the cover card and a few section headers. */
export function Corner({ corner = "tl" }: { corner?: "tl" | "tr" | "bl" | "br" }) {
  const flipX = corner === "tr" || corner === "br";
  const flipY = corner === "bl" || corner === "br";
  return (
    <svg
      className="sprig"
      width={120}
      height={120}
      viewBox="0 0 120 120"
      aria-hidden="true"
      style={{ transform: `scale(${flipX ? -1 : 1}, ${flipY ? -1 : 1})` }}
    >
      <path d="M4 116C10 78 26 44 60 22c14-9 30-14 46-16" />
      <path d="M14 96c-4-14-1-26 8-34 6 12 4 25-8 34z" className="leaf" />
      <path d="M30 70c-8-11-9-24-3-33 10 9 12 22 3 33z" className="leaf" />
      <path d="M52 44c-10-8-14-20-11-30 12 6 17 18 11 30z" className="leaf" />
      <g>
        <circle cx="78" cy="20" r="7" className="petal" />
        <circle cx="78" cy="20" r="2.4" className="heart-dot" />
      </g>
      <g>
        <circle cx="98" cy="34" r="5" className="petal" />
        <circle cx="98" cy="34" r="1.8" className="heart-dot" />
      </g>
      <g>
        <circle cx="60" cy="10" r="4.5" className="petal" />
        <circle cx="60" cy="10" r="1.6" className="heart-dot" />
      </g>
    </svg>
  );
}

/** Coptic cross — stands in for the castle motif; this wedding is in a church. */
export function Cross({ size = 44 }: { size?: number }) {
  return (
    <svg
      className="sprig"
      width={size}
      height={size * 1.4}
      viewBox="0 0 40 56"
      aria-hidden="true"
    >
      <line x1="20" y1="4" x2="20" y2="52" strokeWidth="1.4" />
      <line x1="4" y1="20" x2="36" y2="20" strokeWidth="1.4" />
      <circle cx="20" cy="20" r="7.5" strokeWidth="1.2" />
      <path d="M12 47c5-3 11-3 16 0" />
    </svg>
  );
}
