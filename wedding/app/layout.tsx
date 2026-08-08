import type { Metadata, Viewport } from "next";
import { Cormorant_Garamond, EB_Garamond, Pinyon_Script } from "next/font/google";
import { couple, wedding } from "@/lib/config";
import "./globals.css";

const display = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  style: ["normal", "italic"],
  variable: "--font-display",
  display: "swap",
});

const body = EB_Garamond({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  style: ["normal", "italic"],
  variable: "--font-body",
  display: "swap",
});

/* the calligraphy hand — salutation and signature only */
const script = Pinyon_Script({
  subsets: ["latin"],
  weight: ["400"],
  variable: "--font-script",
  display: "swap",
});

const title = `${couple.pair} — ${wedding.dateLabel.day} ${wedding.dateLabel.month} ${wedding.dateLabel.year}`;

export const metadata: Metadata = {
  title,
  description: `You're invited to the wedding of ${couple.first} and ${couple.second} at ${wedding.ceremony.name}, ${wedding.dateLabel.weekday} ${wedding.dateLabel.day} ${wedding.dateLabel.month} ${wedding.dateLabel.year}.`,
  openGraph: {
    title,
    description: `${wedding.ceremony.name} · ${wedding.dateLabel.weekday} ${wedding.dateLabel.day} ${wedding.dateLabel.month} ${wedding.dateLabel.year}`,
    type: "website",
  },
  robots: { index: false, follow: false }, // a private invitation, not a public page
};

export const viewport: Viewport = {
  themeColor: "#4A6141",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${script.variable}`}>
      <body>{children}</body>
    </html>
  );
}
