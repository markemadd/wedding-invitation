# Mizan — Higgsfield video prompts

Two ready-to-shoot, scene-by-scene scripts for Higgsfield. Both are **vertical
9:16** (Reels / TikTok / Shorts). Each scene names the **source screenshot** to
feed Higgsfield's image-to-video, the **camera preset**, the **on-screen
action**, and the **voiceover / caption**.

Assets in `Screenshots/`: `onboarding-intro.png`, `onboarding-profile.png`,
`wallet.png`, `add.png`, `insights.png`, `buckets.png`, `bills.png`.

Global look (paste into Higgsfield's style/negative fields for every scene):
- **Style:** clean modern fintech, soft natural daylight, real hand holding a
  black iPhone 16 Pro Max, shallow depth of field, subtle screen glow, calm
  premium feel. Egyptian urban setting (Cairo café / desk by a window).
- **Screen realism:** the phone screen shows the provided screenshot EXACTLY —
  do not redesign, relabel, or invent UI. Keep all numbers and Arabic/English
  text unchanged.
- **Negative:** no warped text, no gibberish UI, no extra fingers, no fake
  logos, no flicker, no melting screens, no distorted hands.
- **Color grade:** Mizan green (#3DA35D) accents, bright neutral background.

---

## VIDEO 1 — Product demo: "Take control of your money" (~35s)

Hook-first, screen-led. A young professional sets up Mizan and sees their whole
financial life in one place. One continuous "day in the life" feel.

**Music:** upbeat, minimal, optimistic lo-fi/house, ~110 BPM, soft downbeat on
each screen transition.

| # | Source image | Duration | Camera (Higgsfield preset) | On-screen action | Voiceover / caption |
|---|---|---|---|---|---|
| 1 | `onboarding-intro.png` | 3s | **Push-in** slow on the phone in hand | Screen glows on; "Take control of your money" | VO: "Meet Mizan — your money, finally in one place." |
| 2 | `onboarding-profile.png` | 3s | **Handheld sway**, slight parallax | Thumb taps **Get started** | Caption: "Set up in seconds — everything stays on your iPhone." |
| 3 | `wallet.png` | 5s | **Crash-zoom out** from the budget bar to full screen | Budget bar fills to 36%; balance counts up to 102,793 | VO: "See your balance, your budget, and where your money goes — instantly." |
| 4 | `add.png` | 4s | **Top-down tilt**, finger enters frame | Thumb taps the amount field, then **Save transaction** | Caption: "Add anything in two taps. Or let SMS + receipts do it for you." |
| 5 | `insights.png` | 5s | **Vertical parallax pan** down the charts | Net-worth line draws in; income/spend bars rise | VO: "Insights that actually make sense — net worth, savings rate, and a forecast." |
| 6 | `buckets.png` | 4s | **Push-in** on the budget rings | Rings animate to their fill % | Caption: "Give every pound a job with smart budgets." |
| 7 | `bills.png` | 4s | **Slow orbit / 3D rotate** on the green card | "4,269 EGP" and subscription rows slide up | VO: "Never get surprised by a subscription again." |
| 8 | `wallet.png` | 4s | **Pull-back** to the phone resting on a desk, Mizan on screen | Screen dims to the logo | VO: "Mizan. Private, on-device, and beautifully simple." Caption: "Download on the App Store." |

**End card (static, 3s):** Mizan leaf logo on white, tagline **"Your money.
On your device."** + App Store badge.

Assembly in Higgsfield: generate each row as one image-to-video clip (image =
source screenshot, motion = preset, length = duration), then stitch 1→8 in
order. Add the VO with Higgsfield **Speak** or an external VO, and the captions
as burned-in text. Keep cuts on the music downbeat.

---

## VIDEO 2 — Influencer endorsement: "The app I wish I had at 22" (~30s)

Talking-head creator to camera, intercut with app screens. Authentic, fast,
personal. Use Higgsfield **Speak** (talking avatar / lip-sync) for the creator,
and image-to-video for the app cutaways.

**Creator:** relatable Egyptian finance creator, mid-20s, casual, filming
selfie-style in a café or home office, natural light, warm and genuine — not
salesy.

**Music:** low, warm, confident beat under the voice; lifts at the CTA.

| # | Shot | Source | Duration | Camera / motion | Script (creator VO, lip-synced) |
|---|---|---|---|---|---|
| 1 | Creator to camera | Higgsfield Speak avatar | 4s | Handheld selfie, **slow push-in** | "Okay, if you're Egyptian and terrible with money — watch this." |
| 2 | App cutaway | `wallet.png` | 4s | **Crash-zoom** into the budget bar | "This is Mizan. It shows my balance, my budget, everything — in one screen." |
| 3 | Creator | Speak avatar | 3s | Handheld, tiny **whip-pan** in | "And it's not another app that begs for your bank login." |
| 4 | App cutaway | `onboarding-profile.png` | 3s | **Push-in** on "Everything stays on this device" | "Everything stays on your phone. Nothing leaves. No accounts." |
| 5 | App cutaway | `insights.png` | 4s | **Parallax pan** over the charts | "It literally forecasts my net worth. I've never felt this in control." |
| 6 | App cutaway | `bills.png` | 3s | **3D rotate** on the green card | "It caught two subscriptions I forgot I was paying for." |
| 7 | Creator | Speak avatar | 4s | Push-in, warm smile | "Free, private, made for us. Do future-you a favor." |
| 8 | End card | `wallet.png` blurred + logo | 5s | **Pull-back** + logo pop | "Mizan. Link's in my bio." Caption: **"Search 'Mizan' on the App Store."** |

**On-screen text overlays (burned in):** Scene 1 "POV: you finally get your money
together" · Scene 4 "100% on-device 🔒" · Scene 6 "found 2 forgotten subs 😳" ·
Scene 8 "@yourhandle · #Mizan #بريفيست_مصر".

**Two-language tip:** duplicate Video 2 with an Arabic VO of the same script for
the Egyptian audience; the screens already read in both languages, so only the
Speak track changes.

---

### Notes / what's still capturable
- The onboarding carousel has **3 pages**; only page 1 (`onboarding-intro.png`)
  is captured. Pages 2–3 and the **Settings**, **Plan (goals/wishlist/debts)**,
  **AI**, and **month-story share card** screens can be captured on request for
  extra cutaways.
- For a richer `add.png`, the manual-entry form can be pre-filled (amount +
  merchant + category) instead of blank.
