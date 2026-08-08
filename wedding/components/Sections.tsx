import Image from "next/image";
import { couple, wedding } from "@/lib/config";
import cross from "@/public/cross.png";
import monogram from "@/public/monogram.png";
import garden from "@/public/garden.png";
import { Corner, Cross, Divider, Sprig } from "./Ornaments";
import Reveal from "./Reveal";

/* ── hero ─────────────────────────────────────────────────────────────────
   The names sit on the mural's blush sky; the garden itself anchors the foot
   of the screen. The image is 1080px wide, so it is never stretched past its
   own resolution — it spans the viewport and crops at the edges instead.    */

export function Hero() {
  return (
    <header className="hero section--flush">
      <div className="hero__top">
        <div className="hero__ornament">
          <Divider width={220} />
        </div>
        <p className="eyebrow eyebrow-rule">Welcome to our wedding</p>

        <h1 className="hero__names">
          <span>{couple.first.toUpperCase()}</span>
          <em className="script">&amp;</em>
          <span>{couple.second.toUpperCase()}</span>
        </h1>

        <p className="hero__date">
          {wedding.dateLabel.weekday} {wedding.dateLabel.day}{" "}
          {wedding.dateLabel.month} {wedding.dateLabel.year}
        </p>

        {/* the note sits on its envelope, as if just taken out of it */}
        <div className="envelope-scene">
          <div className="envelope" aria-hidden="true">
            <span className="envelope__flap" />
            <span className="envelope__seam" />
            <Image className="envelope__mark" src={monogram} alt="" sizes="4rem" />
          </div>

          <div className="welcome note">
            <p className="welcome__salutation">{wedding.welcome.salutation}</p>
            {wedding.welcome.body.map((line) => (
              <p key={line} className="welcome__body">{line}</p>
            ))}
            <p className="welcome__valediction">{wedding.welcome.valediction}</p>
            <p className="welcome__signature">{wedding.welcome.signature}</p>
          </div>
        </div>
      </div>

      <div className="garden garden--hero">
        <Image src={garden} alt="" priority sizes="100vw" />
      </div>
    </header>
  );
}

/* ── ceremony info ────────────────────────────────────────────────────── */
/* Names only — where, and what time, live in Church Details and the day's
   Schedule. Stating a time here too would make three places to keep in sync. */

export function CeremonyInfo() {
  const { parents } = wedding;
  const hasParents =
    parents.bride.names.some(Boolean) || parents.groom.names.some(Boolean);

  return (
    <Reveal className="section">
      <p className="eyebrow eyebrow-rule">Ceremony Info</p>

      {hasParents && (
        <>
          <p className="lede">With grateful hearts and great joy, the families of</p>

          {/* the fathers lead, then the couple whose names carry theirs forward */}
          <div className="parents">
            {[couple.parentsFirst, couple.parentsSecond].map((side, i) => (
              <div key={i} className="parents__col">
                <p className="parents__title">{side.title}</p>
                {side.names.filter(Boolean).map((n) => (
                  <p key={n} className="parents__name">{n}</p>
                ))}
                {side.address && <p className="parents__address">{side.address}</p>}
              </div>
            ))}
          </div>
        </>
      )}

      <p className="lede">invite you to attend the wedding of</p>

      {/* stacked, so a long name never splits across a line break */}
      <p className="announce">
        <span>{couple.firstFull}</span>
        <em className="script">&amp;</em>
        <span>{couple.secondFull}</span>
      </p>

      {/* the couple's own watercolour cross, standing where the drawn one was */}
      <Image className="ceremony__cross" src={cross} alt="" sizes="7.5rem" />
    </Reveal>
  );
}

/* ── venue details (reception) ───────────────────────────────────────────
   Where only — the time lives once, in the day's Schedule below. */

export function VenueDetails() {
  const { reception } = wedding;
  return (
    <Reveal className="section">
      <Divider width={200} />
      <p className="eyebrow">Venue Details</p>
      <p className="lede">We invite you to celebrate with us at</p>

      <div className="card venue-card">
        <span className="venue-card__corner"><Corner corner="tr" /></span>
        <h3 className="venue-card__name">{reception.name}</h3>
        <p className="venue-card__address">{reception.address}</p>
        {reception.mapUrl ? (
          <a className="btn btn--quiet" href={reception.mapUrl} target="_blank" rel="noopener noreferrer">
            Open in Maps
          </a>
        ) : (
          <span className="btn btn--quiet" aria-disabled="true">Location to come</span>
        )}
      </div>
    </Reveal>
  );
}

/* ── schedule ─────────────────────────────────────────────────────────── */

export function Schedule() {
  return (
    <Reveal className="section">
      <p className="eyebrow eyebrow-rule">Wedding Day Schedule</p>

      <div className="timeline">
        <span className="timeline__sprig timeline__sprig--top"><Sprig /></span>
        <ol>
          {wedding.schedule.map((row) => (
            <li key={row.time + row.label}>
              <span className="timeline__time">{row.time}</span>
              <span className="timeline__dot" aria-hidden="true" />
              <span className="timeline__label">{row.label}</span>
            </li>
          ))}
        </ol>
      </div>
    </Reveal>
  );
}

/* ── church details ───────────────────────────────────────────────────── */
/* Where only — the time lives once, in the day's Schedule below. */

export function ChurchDetails() {
  const { ceremony } = wedding;
  return (
    <Reveal className="section">
      <p className="eyebrow eyebrow-rule">Church Details</p>
      <p className="venue-card__name" style={{ fontFamily: "var(--display)", fontSize: "1.5rem" }}>
        {ceremony.name}
      </p>
      <p className="lede">{ceremony.address}</p>

      <div className="map">
        <iframe
          title={`Map to ${ceremony.name}`}
          loading="lazy"
          referrerPolicy="no-referrer-when-downgrade"
          src={`https://maps.google.com/maps?q=${encodeURIComponent(ceremony.mapQuery)}&output=embed`}
        />
      </div>

      {ceremony.mapUrl ? (
        <a className="btn btn--quiet" href={ceremony.mapUrl} target="_blank" rel="noopener noreferrer">
          Open in Maps
        </a>
      ) : (
        <span className="btn btn--quiet" aria-disabled="true">Directions to come</span>
      )}
    </Reveal>
  );
}

/* ── gifts ────────────────────────────────────────────────────────────── */

export function Gifts() {
  return (
    <Reveal className="section">
      <Divider width={200} />
      <p className="eyebrow">Gifts</p>
      <p className="lede">
        Your presence is the gift — nothing else is expected. If you&rsquo;d like to
        mark the day with something, we&rsquo;ve put a short list together.
      </p>
      {wedding.giftUrl ? (
        <a className="btn" href={wedding.giftUrl} target="_blank" rel="noopener noreferrer">
          See the gift list
        </a>
      ) : (
        <span className="btn" aria-disabled="true">List coming soon</span>
      )}
    </Reveal>
  );
}

/* ── closing ──────────────────────────────────────────────────────────── */

export function Closing() {
  const note = wedding.closingNote;
  return (
    <Reveal className="section closing">
      {note && (
        <div className="closing__note">
          <Divider width={150} />
          <p className="closing__note-line">
            {note.line}
            <em>{note.emphasis}</em>
          </p>
          <p className="closing__note-plain">{note.plain}</p>
        </div>
      )}

      <p className="closing__line">Your presence would mean the world to us.</p>

      <p className="closing__names">
        {couple.pair}
      </p>
      <p className="closing__date">26 . 09 . 2026</p>

      {/* the garden closes the page as it opened it */}
      <div className="garden garden--closing">
        <Image src={garden} alt="" sizes="100vw" />
      </div>
    </Reveal>
  );
}

/* ── verse ────────────────────────────────────────────────────────────── */

export function Verse() {
  return (
    <Reveal className="section">
      <Divider width={170} />
      <p className="verse">&ldquo;{wedding.verse.text}&rdquo;</p>
      <p className="eyebrow" style={{ fontSize: "0.85rem" }}>{wedding.verse.source}</p>
      <Divider width={170} />
    </Reveal>
  );
}
