"use client";

import { useState } from "react";
import { wedding } from "@/lib/config";
import type { Wish } from "@/lib/db";
import CalendarCard from "./CalendarCard";
import Countdown from "./Countdown";
import Cover from "./Cover";
import MusicToggle from "./MusicToggle";
import Rsvp from "./Rsvp";
import Story from "./Story";
import Wishes from "./Wishes";
import {
  CeremonyInfo,
  ChurchDetails,
  Closing,
  Hero,
  Verse,
  VenueDetails,
} from "./Sections";

/**
 * Section order: welcome + envelope (in Hero) → the story → the verse →
 * ceremony info (names) → church details → venue details → the calendar →
 * countdown → RSVP → wishes → closing. Church comes before venue because
 * that is the order of the day, and each carries its own time.
 */
export default function Invitation({ wishes }: { wishes: Wish[] }) {
  const [opened, setOpened] = useState(false);

  return (
    <>
      <Cover onOpen={() => setOpened(true)} />

      <main className="page" aria-hidden={!opened}>
        <Hero />
        <Story />
        <Verse />
        <CeremonyInfo />
        <ChurchDetails />
        <VenueDetails />
        <CalendarCard />
        <Countdown />
        <Rsvp />
        <Wishes initial={wishes} />
        <Closing />
      </main>

      <MusicToggle src={wedding.music} armed={opened} />
    </>
  );
}
