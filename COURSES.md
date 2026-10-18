# Courses (SwiftUI port of the web apps)

A new **Courses** tab lists five courses: Fret by Fret, Atlas, Py by Py, Slide by Slide
and Desk Skills. All five run on one engine, a port of the web apps' shared JavaScript
engine (batches, Match then Type levels, spaced review, weak spots, "I was right").

## Layout

| Path | What it is |
|---|---|
| `MotAMot/Decks/DeckModel.swift` | Card / question types, JSON loading, tiny HTML-to-text helper |
| `MotAMot/Decks/DeckGrading.swift` | Typed-answer marking (accents, synonyms, notes, chords) |
| `MotAMot/Decks/DeckStore.swift` | Progress, batches, review schedule, quiz engine, backup |
| `MotAMot/Decks/DeckRich.swift` | Web view for the visuals (code, tables, SVG, maps, fretboards, slide demos) |
| `MotAMot/Decks/Deck*View.swift` | Course list, home, study/quiz/result, cards browser, settings |
| `MotAMot/Decks/Resources/*.json` | Each course's cards, generated from `web/<course>/index.html` |
| `tools/export_decks.js` | Regenerates the JSON: `node tools/export_decks.js` |

Mot à Mot's own code is untouched apart from one new `Tab` case and one tab in `MotAMotApp.swift`.
Progress is saved per course in `deck-<slug>-progress.json`, in the same format as the web
apps' backup, so a web backup can be pasted into the matching course (Settings > Backup).

## Not done yet

- Map-tap questions (Atlas, 159 cards) and fretboard-tap questions (Fret, 89 cards). Those
  cards can still be studied and asked in the forward direction.
- Ear training and anything with sound (46 Fret cards are study-only), the Fret Library
  tab (pedal and tone simulator) and the Py "Run it" / Playground (needs Pyodide).
- Slide by Slide's Demos tab and Atlas's extras.
- Not compiled or run on a device: this was written without Xcode. Expect to fix a few build errors.
