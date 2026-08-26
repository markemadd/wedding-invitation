"use client";

import { couple, wedding, weddingDate } from "@/lib/config";
import { Corner } from "./Ornaments";
import Reveal from "./Reveal";

const DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

/** September 2026 laid out Monday-first, with the wedding day ringed. */
function monthGrid(year: number, month: number) {
  const first = new Date(Date.UTC(year, month, 1));
  const lead = (first.getUTCDay() + 6) % 7; // Monday = 0
  const length = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();

  const cells: (number | null)[] = Array(lead).fill(null);
  for (let d = 1; d <= length; d++) cells.push(d);
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

function icsFile() {
  const stamp = (d: Date) => d.toISOString().replace(/[-:]/g, "").split(".")[0] + "Z";
  const end = new Date(weddingDate.getTime() + 8 * 3600 * 1000);
  const esc = (s: string) => s.replace(/([,;\\])/g, "\\$1");

  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Maria and Joseph//Wedding//EN",
    "BEGIN:VEVENT",
    "UID:maria-joseph-2026@wedding",
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(weddingDate)}`,
    `DTEND:${stamp(end)}`,
    `SUMMARY:${esc(`The wedding of ${couple.pair}`)}`,
    `LOCATION:${esc(`${wedding.ceremony.name}, ${wedding.ceremony.address}`)}`,
    `DESCRIPTION:${esc(
      `Ceremony at ${wedding.ceremony.timeLabel}. Reception to follow at ${wedding.reception.timeLabel}, ${wedding.reception.name}.`
    )}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");
}

export default function CalendarCard() {
  const year = weddingDate.getFullYear();
  const month = weddingDate.getMonth();
  const day = Number(wedding.dateLabel.day);
  const cells = monthGrid(year, month);

  function download() {
    const blob = new Blob([icsFile()], { type: "text/calendar;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "maria-and-joseph.ics";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  return (
    <Reveal className="section">
      <div className="card calendar">
        <span className="calendar__corner calendar__corner--tl"><Corner corner="tl" /></span>
        <span className="calendar__corner calendar__corner--br"><Corner corner="br" /></span>

        <h2 className="calendar__title">
          {wedding.dateLabel.month} {year}
        </h2>

        <table className="calendar__grid">
          <thead>
            <tr>
              {DAYS.map((d) => (
                <th key={d} scope="col">{d}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: cells.length / 7 }, (_, row) => (
              <tr key={row}>
                {cells.slice(row * 7, row * 7 + 7).map((d, i) => (
                  <td key={i}>
                    {d && (
                      <span className={d === day ? "is-wedding" : undefined}>
                        {d === day && <span className="sr-only">Wedding day: </span>}
                        {d}
                      </span>
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <button className="link-underline" type="button" onClick={download}>
        Add to Calendar
      </button>

      <a className="btn" href="#rsvp">RSVP</a>
    </Reveal>
  );
}
