# Mot à Mot — iPhone app

A native SwiftUI rebuild of the web app. Same word list, same batches, same tests —
but it runs offline, sits on your home screen, and can use the **Enhanced and
Premium French voices**, which Safari refuses to hand to a web page.

The project is already made. You don't have to create a target or drag files in.

---

## 1. Open it (2 minutes)

1. Make sure **Xcode** is installed (free, from the Mac App Store). Open it once
   and let it finish installing components.
2. Double-click **`MotAMot.xcodeproj`**. Xcode opens with the whole app in the
   sidebar.

## 2. Tell Xcode who you are

1. Click **MotAMot** at the very top of the left sidebar (the blue icon).
2. Select the **MotAMot** target → **Signing & Capabilities** tab.
3. Tick **Automatically manage signing**.
4. **Team**: choose **Add an Account…**, sign in with your Apple ID, then pick
   your name (Personal Team).
5. If it complains that the bundle identifier is taken, change **Bundle
   Identifier** to something unique — e.g. `com.mohau.motamot2`.

## 3. Run it on your iPhone

1. Plug the iPhone into the Mac, unlock it, tap **Trust** if asked.
2. In the toolbar, click the device dropdown (it probably says a simulator) and
   choose **your iPhone**.
3. Press **⌘R**.
4. The first run stops on the phone with *"Untrusted Developer"*. On the iPhone:
   **Settings → General → VPN & Device Management → your Apple ID → Trust**.
   Press ⌘R again.

To just try it without the phone, pick any simulator and press ⌘R — but the good
voices only exist on a real device.

## 4. Get the voice that made this worth doing

On the iPhone: **Settings → Accessibility → Spoken Content → Voices → French**,
and download a **French (France)** voice marked **Enhanced** or **Premium**.

Then in the app: **Settings → Voice**. The voice appears in the list with its
quality next to it. Pick it and tap the test line. This is the thing the website
cannot do.

## 5. Bring your progress across

On the web app: **Settings → Backup → Copy code**. Email or AirDrop it to
yourself, then in the iPhone app: **Settings → Backup → paste → Restore
progress**. The save format is identical in both directions, so you can go back
to the web version later without losing anything.

---

## The free Apple ID limit

With a free account the app **stops opening after 7 days**. To renew it, plug the
phone in and press ⌘R again — your progress stays, because it lives on the phone,
not in the build. A paid developer account ($99/year) makes each build last a
year.

## What's in the project

| File | What's in it |
|---|---|
| `MotAMotApp.swift` | App entry, the four tabs, the full-screen study/test flow |
| `Model.swift` | The `Word` type, the bundled word list, contractions, the forms index |
| `Answers.swift` | Marking typed answers — French accents, English synonyms, plurals, UK/US spelling, typos |
| `Store.swift` | Progress: batches, spaced review, settings, backup codes, sentence pool |
| `Quiz.swift` | The test engine: questions, scoring, the spaced schedule, "I was right" |
| `Speech.swift` | Voices and speaking (`AVSpeechSynthesizer`) |
| `Theme.swift` | Colours, cards, buttons — the paper-and-indigo look from the web app |
| `WordCard.swift` | The word card, example sentences, form notes, the grammar explainer |
| `LearnView.swift` | Home: progress, the batch, the level ladder, finished batches |
| `StudyView.swift` | Flashcards, with swipe |
| `QuizView.swift` | Match / Type French / Type English, feedback, results |
| `ReadView.swift` | Wikipedia passages and sentence practice |
| `WordsView.swift` | The searchable 2,190-word list |
| `SettingsView.swift` | Everything adjustable |
| `Resources/words.json` | 2,190 words with meanings, genders, examples and form labels |
| `Resources/forms_index.txt` | 29,000 French surface forms → word, for the Read tab |

## What's the same as the web app, and what isn't

**Same:** the word list and its ranking, batches that grow with your first-try
average, a third of each batch as revision of words you've struggled with, the
Match and Type levels with your pass mark, finished-batch practice including Type
English with the "I was right" button, spaced review (1, 3, 7, 14, 30, 60, 120
days), contractions spelled out, form labels and the dictionary-form sentences,
Wikipedia reading with your known words highlighted, sentence practice, the word
list, backup codes, skip-ahead, light/dark.

**Better:** Enhanced and Premium voices, works with no signal, real app launch,
no browser chrome, and the keyboard behaves.

**Dropped:** the human recordings from Wikimedia — they were slow, you had them
switched off, and a Premium voice is better than a patchy recording.

## If the build fails

I wrote this without a Mac to compile on, so a first build may want one or two
small corrections. Click the red ❗in the left sidebar, copy the message plus the
file and line, and send it to me — these are normally one-line fixes.
