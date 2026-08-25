# Screenshots and App Preview

The media is **not made by hand and is not in git** — the scripts below produce
it. Uploading is manual: in App Store Connect drag the files into the *App
Preview and Screenshots* section (language switch at the top, one locale at a
time).

## What the scripts produce

| What | Where | Resolution | Count |
|---|---|---|---|
| iPhone 6.5" screenshots | `screenshots/<locale>/iphone-6.5/` | 1242 × 2688 | 8 |
| iPad 13" screenshots | `screenshots/<locale>/ipad-13/` | 2064 × 2752 | 8 |
| The same with captions | `screenshots-captioned/<locale>/<device>/` | same | 8 + 8 |
| iPhone App Preview | `preview/<locale>/iphone-6.5.mp4` | 886 × 1920, 30 fps, AAC | 1 |
| iPad 13" App Preview | `preview/<locale>/ipad-13.mp4` | 1200 × 1600, 30 fps, AAC | 1 |

**iPhone 6.5" is the slot this listing uses.** Apple derives every *smaller*
size from the file you upload, but only within a slot — the slot is picked per
upload in Connect, and a listing sitting on the 6.5" slot refuses a 6.9" file
outright. Shooting one iPhone size rather than two halves the run. If the 6.9"
slot is ever wanted as well, add *iPhone 17 Pro Max* at 1320 × 2868 back
alongside the 6.5" device in `appstore_media.sh`; `shoot` already takes the
device and its expected size as arguments.

The App Preview has no such split: the one 886 × 1920 file is what Apple lists
for the 6.9", 6.5", 6.3" and 6.1" displays alike, so `iphone-6.5.mp4` is the
video for every iPhone slot.

The locales are `cs` and `en-US`, everything in portrait. `en-GB` gets no media
of its own — upload the `en-US` set into it.

```bash
Tools/appstore_media.sh              # screenshots and videos
Tools/appstore_media.sh screenshots  # screenshots only (~4 min)
Tools/appstore_media.sh video        # videos only (~6 min)
Tools/appstore_captions.sh           # paints captions onto finished screenshots (~1 min)
```

**Upload either the captioned set or the plain one** — both have the same file
names and order, they differ only in the band at the top. Captions are not
compulsory, but they lift conversion, and for this app they are where the "no
ads, no purchases" promise gets to be said out loud.

`appstore_media.sh` needs Xcode, the *iPad Pro 13-inch (M5)* simulator,
ImageMagick (`brew install imagemagick`) and Python 3 (for the preview's music
bed). The iPhone one is *iPhone 11 Pro Max* — Xcode ships the device type but
does not always leave a ready-made simulator for it, so the script creates one
on the newest installed runtime if it has to.

## How the poses work

Nothing here is mocked up. Every shot is a **numbered deal played forward by the
app's own move advisor** — the same suggestions the Hint button offers, taken
best-first — or one of the QA scenarios the tests already use. The catalogue is
`Shots.catalogue` in [`solitaire/Support/ScreenshotScenes.swift`](../solitaire/Support/ScreenshotScenes.swift),
which is `#if DEBUG` and reaches no App Store build; the script picks a pose with
`-shot <name>`.

That is a deliberate trade. A mocked board would be quicker to write and would
quietly drift away from the game as the game changed; a board reached by legal
moves either still plays or stops rendering, and the score, the clock and the
move count on it are the ones the deal actually earned.

The seeds were chosen by compiling the engine on its own — the same trick
`Tests/run.sh` uses — and playing it through hundreds of thousands of deals,
scoring each resulting board on what photographs well: cards on all four
foundations, a waste fan, no empty column, something still face down to look at.
A few are rarer than that:

- **`03-stuck`** needed a deal the advisor plays to a *genuine* dead end — no
  legal move anywhere, recycling included. Under draw 1 with unlimited passes
  those are roughly one deal in tens of thousands.
- **`02-autofinish`** and **`06-win`** needed a deal the advisor plays all the
  way to the point where the win is guaranteed and the wand appears. About one
  deal in a hundred. Both use the same seed: one stops at the wand, the other
  taps it, so the results screen shows a win that was really played.

A pose is built *synchronously*, before the first frame is drawn, so nothing
waits for the game to get anywhere. What the script waits for is SwiftUI
settling — a sheet presenting, the wand springing in, the cascade landing — and
it waits for a **marker file** the app drops when the pose is ready
(`Shots.markReady`), not for a guessed number of seconds.

Every pose also clears the statistics table before it finishes. The eight shots
run one after another against a single install, and a pose that did not clear
the slate would photograph whatever the shot before it left behind.

## The eight shots, in order

The order matters more than the count: most people never scroll past the second
one, so the first two have to carry the app on their own.

| # | Shot | What it shows |
|---|---|---|
| 1 | `01-board` | The hero. Deal 16371 at draw 3, 34 moves in: all four foundations open, every column still holding something, three cards fanned on the waste. |
| 2 | `02-autofinish` | Deal 6477 played to the point where the win is guaranteed and the wand offers to finish it. This is where the "no ads" caption goes. |
| 3 | `03-stuck` | The dead-end banner — the one feature in the listing no competitor can copy. |
| 4 | `04-hint` | A hint ring on the card the advisor would play next. |
| 5 | `05-vegas` | Vegas scoring with a balance carrying between deals, on the wine felt. |
| 6 | `06-win` | The results screen after deal 6477 was played out: real time, real moves, real time bonus. |
| 7 | `07-stats` | The statistics table, filled in by playing the real bookkeeping rather than by writing numbers into it. |
| 8 | `08-settings` | Draw count, scoring mode, four felts, four card backs, left-handed layout. |

Between them the set shows all four table felts and all four card backs.

**A hint fades after 2.6 seconds**, which is shorter than the round trip from
the marker being written to the screenshot being taken, so `04-hint` asks for
the ring again every two seconds and declares itself ready almost immediately.
The picture is normally the *first* suggestion; if the script is having a slow
day it is the second, which is still a real suggestion rather than an empty
board.

## Captions

`Tools/appstore_captions.sh` paints a band at the top of each shot in the felt's
own dark green, with the screenshot scaled — never cropped — underneath it. The
text lives in `en_caption` and `cs_caption` in that script, two hand-broken lines
each.

## App Preview

Two recordings, cut into one 25-second preview per device:

- **`preview-play`** — deal 16371 dealt with the dealing animation on and handed
  to the advisor bot (`-autoplay`), which plays a move every 200 ms. The staggered
  deal is the opening shot.
- **`preview-finish`** — the nearly-won board, with the pose tapping the wand two
  seconds in, so the clip opens on a board and everything after that is the
  cascade of cards flying to the foundations and then the confetti.

Every cut window is chosen to hold something *moving* from its first frame to its
last. Two things bound them, and both were learned the hard way on the sister
projects: the confetti window is short on purpose (it flies for about two seconds
and then the results panel just sits there), and nothing may reach past about
21 s into a recording, where the tail stops being reliably decodable and a
crossing range silently freezes on one frame.

Nothing fails loudly if a window drifts — it just goes still. So after any change
to the pacing, the poses or the animations, look at the frames either side of each
cut before uploading:

```bash
swift Tools/appstore_frames.swift AppStore/preview/en-US/iphone-6.5.mp4 \
    /tmp/frames 0.1 4.7 4.9 10.7 10.9 16.1 16.3 22.4 22.6 24.9
magick montage /tmp/frames/*.png -tile 5x -geometry 200x+4+4 /tmp/sheet.png
```
