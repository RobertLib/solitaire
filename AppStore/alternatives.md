# ASO: the reasoning, the competition, and the alternatives

Numbers in brackets are character counts. The limits are 30 for the name, 30 for
the subtitle and 100 for keywords.

## What we are up against

Every one of these was looked at on the store before the copy in this directory
was written. Ratings are the US storefront unless marked.

| App | Subtitle | Developer | Ratings | Rating | Money |
|---|---|---|---|---|---|
| Solitaire | Fun Classic Klondike Card Game | MobilityWare | 2 056 714 | 12+ | Free + IAP |
| ⋆Solitaire: Classic Card Games | Relax with Classic Solitaire | PlayStudios | 936 970 | 12+ | Free + IAP |
| Solitaire.com: Classic Cards | Patience Puzzle Games | Tripledot | 878 433 | 4+ | Free + IAP |
| Solitaire - Card Solitaire | Fun Classic Solitaire Game! | Doodle Mobile | 662 462 | 4+ | Free + IAP |
| Solitaire by Staple Games | Official Version | Staple Games | 543 044 | 4+ | Free + IAP |
| Vita Solitaire for Seniors | Large Cards Solitaire Games | Vita Studio | 465 916 | 4+ | Free + IAP |
| Solitaire: Cards Games Classic | #1 Classic Solitary Klondike | nerByte | 246 982 | 12+ | Free + IAP |
| Microsoft Solitaire Collection | Play Classic Solitaire Games! | Microsoft | 254 069 | 4+ | Free + IAP |
| Solitaire by MobilityWare | Play Solitaire with NO ads! | MobilityWare | 138 033 | 4+ | **Paid** |
| Solitaire Collection – No Ads! | (collection of 7 games) | Fortuisoft | 4 192 | 4+ | Free |
| No Ads Solitaire | — | Drew Schweinfurth | 10 868 | 4+ | Free |

Four things follow from that table.

**We cannot win the head terms.** Two million ratings sit at the top of
"solitaire", and the next eight apps have half a million each. A new app with no
ratings does not rank on the bare word, whatever it puts in its name. Chasing it
is how you end up with no traffic at all.

**The long tail is winnable, and it is where the intent is.** *solitaire
klondike* is volume 45 at difficulty 21 — the best relevant target found
anywhere, and better than *klondike solitaire* (38 / 30) purely on word order.
*patience card game* is 28 / 26, *classic solitaire* 35 / 21, *klondike
solitaire free* 18 / 14. Someone typing *solitaire no wifi*, *solitaire offline
no ads* or *klondike solitaire free* knows exactly what they want, and it is
exactly this app. The keyword sets are built for those rather than for volume.

**"No ads, no purchases" is the whole differentiator, and this genre proves it.**
MobilityWare — the biggest app in the category — sells a *separate paid app*
whose entire subtitle is "Play Solitaire with NO ads!". There is a visible
cluster of small apps whose names are nothing but that promise. Every large
competitor above monetises with ads or purchases. That is why the promise is in
the subtitle in all three languages, in the caption on the last screenshot, and
in the first paragraph of the description. It is a conversion lever as much as a
keyword.

**Two soft niches are worth aiming at.** *Seniors* is a real segment with a real
app in it (Vita Solitaire for Seniors, 465 916 ratings, on "large cards"), and
this app's Dynamic Type support and full VoiceOver labelling are an honest claim
to it — hence `seniors` in all three keyword sets. And nobody in the category has
**dead-end detection**; it is the one feature in the description that no
competitor can copy from their own listing.

## The Czech storefront is nearly empty, and that is the opportunity

Only three competitors have bothered to localise into Czech at all:

| CZ name | CZ subtitle | Developer | CZ ratings |
|---|---|---|---|
| Solitér: #1 Solitaire Karetní | #1 Pasiáns Solitaire 2026 | nerByte | 4 855 |
| Solitaire - Karetní hra | Hrajte karty každý den! | Easybrain | 6 865 |
| Solitaire.com: Klasické Karty | Původní Karetní Hra Offline | Tripledot | 1 036 |

Everyone else — MobilityWare included, at 8 068 Czech ratings — ships the English
listing into Czechia untouched. The whole Czech market tops out in the single
thousands of ratings, against half a million in the US. This is the storefront
where a good listing actually moves the ranking.

Three findings shaped `cs/`:

- **Czechs type the English spelling.** Searching *pasiáns*, *pasians* and
  *solitér* on the Czech store all return the same English-named apps, so all
  three spellings have to be indexed. The name carries *solitér*, *pasiáns* and
  *solitaire* together for that reason, which also matches how the two localised
  competitors write theirs.
- **"Klondike" is a trap in Czech.** Searching *klondike* on the Czech store
  returns Klondike Adventures, Township, Family Island — farm games, not card
  games. The word is worth a keyword slot (it combines with *pasiáns* in the
  name) but it must not be spent on the name or the subtitle.
- **`Solitér` has to lead the name.** The home-screen name is localised to
  *Solitér*, and the store name must not differ from it in meaning.

## What is in use

```
en-US   Solitaire Klondike: Offline   (27)   Classic patience, no ads ever   (29)
en-GB   Solitaire Klondike: Offline   (27)   Patience card game, no ads      (26)
cs      Solitér: Pasiáns Solitaire    (26)   Offline, zdarma, bez reklam     (27)
```

Between the name and the subtitle, `en-US` indexes *solitaire, klondike,
offline, classic, patience, no, ads* — and because Apple combines terms within a
locale, that assembles *solitaire klondike*, *classic solitaire*, *offline
solitaire*, *klondike patience*, *solitaire no ads* and so on without spending a
single keyword character on any of them.

Note the word order: `Solitaire Klondike`, not `Klondike Solitaire`. Apple
combines terms in any order, so both phrases are covered either way — but the
name reads left to right, and leading with the head term is worth more than
matching the phrase people happen to type more often.

## App name

| Czech | | English | |
|---|---|---|---|
| Solitér: Pasiáns Solitaire | (26) | Solitaire Klondike: Offline | (27) |
| Solitér: Pasiáns bez reklam | (27) | Solitaire Klondike: No Ads | (26) |
| Pasiáns: Klasický solitér | (25) | Solitaire: Classic Klondike | (27) |
| Solitér: Klasický pasiáns | (25) | Klondike Solitaire: No Ads | (26) |
| Solitér: Karetní pasiáns | (24) | Solitaire Patience: Offline | (27) |

Recommendation: keep *offline* in the name. It is the one head-ish term this app
can compete on, because most of the apps that rank for it are lying — they need a
connection for their ad server — and it is the word the target player actually
types. If the name ever needs to change, `Solitaire Klondike: No Ads` is the
straight swap: it trades a term this app can win for a term it can win harder,
and the subtitle then picks up *offline* in its place.

There is no brand name here on purpose. *Ace High* and *Mini Golf 3D: 108 Holes*
both had something to be a brand about; this app is called Solitaire on the home
screen and does one thing. In a category where the top ten names are all the word
plus a qualifier, a made-up brand would cost ranking and buy nothing. If a brand
is ever wanted anyway, put it *after* the head terms — `Solitaire Klondike: Felt`
— never in front of them.

## Subtitle

| Czech | | English | |
|---|---|---|---|
| Offline, zdarma, bez reklam | (27) | Classic patience, no ads ever | (29) |
| Karetní hra zdarma, bez reklam | (30) | Patience card game, no ads | (26) |
| Klasický pasiáns bez reklam | (27) | Classic cards, offline, free | (28) |
| Zdarma, bez reklam a nákupů | (27) | Klondike patience, ad-free | (26) |
| Karetní klasika bez internetu | (29) | No ads, no purchases, ever | (26) |

`en-GB` deliberately overlaps `en-US` rather than filling in its gaps. It is the
second index in the Czech storefront, but it is the *only* index in the UK,
Ireland, Australia and New Zealand — and those are worth far more than Czechia's
second slot, so it gets the strong set rather than the leftovers. What it does
change is the subtitle: *patience* leads it, because outside North America that
is what the game is called. nerByte, the one competitor that varies by region,
does exactly the same thing — their US subtitle says *Klondike*, their European
one says *Patience*.

## Keywords

In use:

```
en-US  free,cards,game,vegas,draw,undo,hints,wifi,internet,seniors,relax,deck,solo,purchases,score,moves  (97)
en-GB  free,vegas,draw,undo,hints,wifi,internet,seniors,relax,deck,solo,purchases,score,moves,stats,timed (98)
cs     karetní,karty,hry,klondike,klasická,nápověda,vegas,internetu,wifi,nákupů,relax,senioři,tahy,skóre  (97)
```

`en-GB` drops *cards* and *game* because its subtitle already carries *card* and
*game*, and Apple pairs a singular with its plural itself; the two freed slots go
to *stats* and *timed*.

Alternative sets, if you end up tuning by performance:

```
# EN, no-freemium angle (leans hardest on the differentiator)
free,noads,nowifi,nointernet,purchases,premium,paid,cards,game,solo,single,player,deck,score  (94)

# EN, accessibility / seniors angle (pairs with a "Large cards, no ads" subtitle)
seniors,elderly,large,big,easy,simple,eyes,relax,calm,free,cards,game,deck,solo,score         (91)

# EN, classic-desktop-nostalgia angle
retro,classic,original,desktop,computer,pc,scoring,vegas,draw,three,one,free,cards,game,deck  (95)

# CZ, klidná hra / relax angle
karetní,karty,hry,jednoduchá,klidná,relax,odpočinek,senioři,nápověda,internetu,wifi,nákupů    (92)

# CZ, výzva a rekordy angle
karetní,karty,hry,klondike,výzva,rekordy,statistiky,tahy,skóre,vegas,čas,nápověda,klasická    (93)
```

Rules, so that editing does not break it:

- Separate with a comma and **no space after the comma** — a space counts towards
  the limit of 100.
- Do not repeat words from the name or the subtitle, Apple indexes those
  separately. **This applies between the name and the subtitle too.** That is why
  *solitaire*, *klondike*, *offline*, *classic* and *patience* are absent from the
  English lists, and *solitér*, *pasiáns*, *offline*, *zdarma* and *reklam* from
  the Czech one.
- Do not put a plural next to its singular ("card" and "cards"), Apple pairs them
  itself. The Czech set bends this once — Apple's Czech stemming is unreliable
  enough that *karty* and *karetní* are both worth their characters, and they are
  different words anyway.
- Do not name competing games — grounds for rejection. This matters more here
  than in the other two projects: *spider*, *freecell*, *pyramid* and *tripeaks*
  are tempting and all of them are other people's app names. They are also
  dishonest, because this app plays none of them.
- Do not use *windows* or *microsoft*. The Standard scoring is the one from the
  desktop game and the description says so in those words, but the trademark is
  not ours to put in an indexed field.
- The word "zdarma"/"free" is only worth using if the game really is free (it is,
  and with no purchases either, which is rarer here than anywhere and worth the
  space).

## Shorter description, if you decide on a terser version

Each paragraph is one long line on purpose. App Store Connect keeps newlines
exactly as pasted, so a paragraph wrapped at 80 columns here comes out ragged on
the device while every other paragraph reflows — paste these as they are.

**EN**

```
Klondike solitaire, done properly. Seven columns, four foundations, draw one or draw three, and the scoring you remember from the desktop — Standard, Vegas, or none at all.

Undo reaches back through the whole game and survives closing the app. Hints cycle through every move worth making. When a deal genuinely has no legal moves left the board says so, instead of leaving you to work it out. Once the win is certain, one tap plays out the rest.

Four felts, four card backs, a left-handed layout, and full VoiceOver, Dynamic Type and Reduce Motion support. Statistics kept separately for draw one and draw three, because one of them is much easier.

No ads. No purchases. No account. No internet.
```

**CZ**

```
Klondike pasiáns, jak má být. Sedm sloupců, čtyři základny, lízání po jedné nebo po třech kartách a bodování, které si pamatuješ z počítače — standardní, Vegas, nebo žádné.

Zpět se dostaneš přes celou hru a přežije to i zavření aplikace. Nápověda projde všechny tahy, které stojí za to udělat. Když v rozdání opravdu žádný tah nezbývá, hra to řekne sama, místo aby tě nechala na to přijít. Jakmile je výhra jistá, zbytek dohraje jedno ťuknutí.

Čtyři sukna, čtyři rubové strany karet, rozvržení pro leváky a plná podpora VoiceOveru, dynamické velikosti písma i omezení pohybu. Statistiky vedené zvlášť pro lízání po jedné a po třech, protože jedno z nich je o dost snazší.

Bez reklam. Bez nákupů. Bez účtu. Bez internetu.
```
