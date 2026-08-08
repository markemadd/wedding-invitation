/**
 * Every detail of the day lives here. Edit this file, not the components.
 */

export const wedding = {
  bride: "Maria",
  groom: "Joseph",

  /** Full names as they should appear in the formal announcement. */
  brideFull: "Maria Amgad Bahaa",
  groomFull: "Joseph Emad Garas",

  /**
   * Shown beneath the announcement, in the same order as the names above it:
   * bride's side first, then groom's.
   */
  parents: {
    bride: { title: "Mr & Mrs", names: ["Amgad Bahaa"], address: "" },
    groom: { title: "Mr & Mrs", names: ["Emad Garas"], address: "" },
  },

  /**
   * The welcome, at the top of the page under the names.
   * `salutation` and `signature` are set in the calligraphy face; `body` stays
   * in the reading face, because four lines of script on a phone is a wall.
   */
  welcome: {
    salutation: "Dear family and friends!",
    body: [
      "We are so happy to invite you to share this meaningful day with us.",
      "Your presence will make our wedding even more special.",
    ],
    valediction: "With love,",
    signature: "Joseph & Maria",
  },

  /** Ceremony — 2:00 PM Cairo time (UTC+3 in September). */
  date: "2026-09-26T14:00:00+03:00",
  dateLabel: { weekday: "Saturday", day: "26", month: "September", year: "2026" },

  ceremony: {
    name: "Saint Mary & Ava Bishoy Church",
    address: "Fifth Settlement, New Cairo, Egypt",
    time: "14:00",
    mapUrl: "https://maps.app.goo.gl/6YktmPeXctiEo5c8A",
    /** Optional "q=" value for the embedded map, e.g. "30.0131,31.4372". */
    mapQuery: "Saint Mary and Ava Bishoy Church, Fifth Settlement, New Cairo",
  },

  reception: {
    name: "The Beach JW Marriott",
    address: "Ring Road, Mirage City, Cairo, Egypt",
    /** Set once you know it — shown in the Reception Info block. */
    time: "18:00",
    mapUrl: "https://maps.app.goo.gl/5phgeT8bHqDD7A849",
    mapQuery: "The Beach JW Marriott Cairo",
  },

  /** The running order shown on the timeline. Add or remove freely. */
  schedule: [
    { time: "14:00", label: "Ceremony" },
    { time: "17:30", label: "Welcome" },
    { time: "18:00", label: "Reception" },
    { time: "19:00", label: "Dinner" },
    { time: "20:00", label: "Cake & Toasts" },
    { time: "23:00", label: "Farewell" },
  ],

  /** Gift registry / redirection link. Empty = the button reads "coming soon". */
  giftUrl: "",

  /** Replies close on this date. */
  rsvpBy: "1 September 2026",

  /** Optional background music file placed in /public (e.g. "/music.mp3"). */
  music: "/music.mp3",

  verse: {
    text: "Therefore what God has joined together, let no one separate.",
    source: "Mark 10 : 9",
  },

  /**
   * The adults-only note, at the very end. Guests skim, so the second line
   * says the thing plainly — the first line is the one that carries the tone.
   * Set to null to drop the whole block.
   */
  closingNote: {
    line: "Kiss your little ones goodnight,",
    emphasis: "and come enjoy the night with us.",
    plain: "An adults-only celebration",
  },
} as const;

export const weddingDate = new Date(wedding.date);

/**
 * Whose name leads. Every place the two names appear together reads this
 * rather than naming a side, so the order can never drift between the cover,
 * the hero, the announcement, the parents' columns and the page title.
 * Flip to ["bride", "groom"] and the whole page follows.
 */
const NAME_ORDER = ["groom", "bride"] as const;

const [lead, second] = NAME_ORDER;

const FULL_NAME = { groom: wedding.groomFull, bride: wedding.brideFull } as const;

export const couple = {
  /** Short names, in reading order. */
  first: wedding[lead],
  second: wedding[second],

  /** Full names, in the same order. */
  firstFull: FULL_NAME[lead],
  secondFull: FULL_NAME[second],

  /** Each side's parents, so the columns sit under their own child. */
  parentsFirst: wedding.parents[lead],
  parentsSecond: wedding.parents[second],

  /** "Joseph & Maria", for titles and calendar entries. */
  get pair() {
    return `${this.first} & ${this.second}`;
  },
} as const;
