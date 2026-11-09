# Setup window design

## The idea: the severed floor

Claude Severance keeps your work accounts and your personal account apart. The setup window shows that split. One vertical seam runs down the middle of the window. The left half is the work floor, a shade paler or deeper than the outside on the right. A band of light travels down the seam, and its colour says what the window is doing.

In light it reads as a quiet mid-century office: off-white walls, green-black ink, a deep carpet green for buttons and switches. In dark it reads as an old phosphor terminal: near-black blue with teal light, and a faint field of digits on the floor while work is under way.

Everything is evocation, not reference. There are no names, logos, characters, quotes or screens from any film or show, and nothing here should need them.

## Layout

A 520 x 640 frameless window. From top to bottom:

1. **Bar** (44 px). The small mark, "Claude Severance Setup", then minimize and close.
2. **Hero.** The mark, sitting on the seam: 64 px, smaller while working and on the accounts screen.
3. **Copy.** The eyebrow (IBM Plex Mono 11 px capitals in the moment's colour), a two-line title (IBM Plex Sans 30 px, the first line Medium, the second Regular and muted), and a lede (Plex Sans 13.5 px, hidden while working).
4. **Body.** A card of 48 px rows separated by hairlines, a numbered step list, or the accounts editor.
5. **Actions.** A primary button (signal on signal ink) and a ghost button, 40 px tall, 8 px corners.
6. **Meta.** Short facts separated by middle dots.
7. **Progress.** A 3 px bar in the moment's colour, shown while working and when done.

Cards have 8 px corners and 1 px hairlines; text fields 6 px. Finished steps are numbered 01, 02, 03 in Plex Mono.

## The moment's colour

| Moment | Screens | Light / dark | Pass |
|---|---|---|---|
| Waiting | welcome (install), accounts | grey-green | 7 s |
| Deciding | welcome (update), confirm (uninstall) | brass | 7 s |
| Working | working, with the digit field | teal | 3.2 s |
| Removing or stopped | removing, failed | rust | 3.2 s |
| Done | ready, removed | green | 5.6 s |

The light starts above the window, runs down the seam behind the mark, leaves at the bottom and rests. The eyebrow, the step numbers and the progress bar take the same colour. With Windows animations turned off, the light holds still on the seam and the digits don't drift.

## Tokens

| Token | Light | Dark |
|---|---|---|
| Canvas (outside) | `#F3F4F1` | `#06141A` |
| Floor (work half) | `#ECEFEA` | `#08191F` |
| Surface | `#FBFCFA` | `#0B1E25` |
| Ink | `#13201C` | `#CFEDEA` |
| Muted | `#55625D` | `#82A9A6` |
| Subtle | `#6F7B76` | `#638B88` |
| Hairline | `#D7DCD6` | `#17323A` |
| Signal / signal ink | `#2F5D4F` / `#F3F4F1` | `#7FD8CF` / `#06141A` |
| Negative | `#B4442E` | `#F0806A` |

Account colours are muted mid-century tones: blue `#3E6FA3`, mustard `#C08A2E`, green `#3E7A5A`, rust `#B4442E`, plum `#6C5B9E`, rose `#B5577A`, teal `#2F8A86` and orange `#C46A2B`. They repeat after eight accounts.

## Type

IBM Plex Sans (Regular, Medium, SemiBold) and IBM Plex Mono (Regular), bundled in `src/fonts` under the SIL Open Font License. Mono is for labels, numbers, commands and paths; Sans for everything else.

## Words

The voice is a calm staff handbook: plain, polite, a little dry.

- Each step has a handbook name: Orientation, Assignments, Procedure in progress, Procedure complete, Reintegration.
- Two-line titles that read as one sentence: "Work stays at work. / Personal stays yours.", "Your accounts / are severed.", "Bring it all / back together?".
- Say what will happen and what stays the same. Every destructive switch says where the backup goes.
- Buttons are verbs, with "Not now", "Keep it" or "Done" as the way out.

## Account icons

Each account's shortcut, Start menu entry and tile use its own logo when one is chosen. Otherwise they use a shell in the account's colour with the first letter of its name. A chosen logo is copied to `%LOCALAPPDATA%\ClaudeSeverance\logos\<id>.png`, fitted on a 256 px transparent square.

## The mark

One disc cut down the middle. The left half, at work, is solid; the right half, outside, is only an outline; the two sit a step apart. It sits on a tile with 22% corners: carpet green with an off-white disc on light grounds, pale teal with a near-black disc on dark grounds.

Files are in `assets/logo`, built by `tools/make-graphics.ps1`. Keep clear space of a quarter of the tile around it. Don't recolour the halves separately, fill in the outlined half, add a ring, or put the mark next to Anthropic's logo.
