# Workout

[![CI](https://github.com/Octavian-Mihai/workout-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/Octavian-Mihai/workout-ios/actions/workflows/ci.yml)

A native iPhone app for strength training, plus a desktop **Program Builder** website. Log sessions with a custom keypad and RIR, build rotating programs, follow recovery and volume, and pull runs from Apple Health. The website assembles programs from the same exercise catalog and exports JSON the app can import.

Requires **iOS 17+**.

This repo has two parts:

- **iPhone app** — SwiftUI client in `WorkoutApp/`
- **Program Builder** — static site in `program-builder/` or [live website](https://program-builder-mu.vercel.app/)

---

## Screenshots

| Home | Logging | Programs |
|:---:|:---:|:---:|
| ![Home screen](website/screens/home.png) | ![Custom keypad with RIR](website/screens/workout_logging.png) | ![Programs tab](website/screens/programs.png) |

| Workout summary | Recovery | Exercise catalog |
|:---:|:---:|:---:|
| ![Workout complete summary](website/screens/workout_complete.png) | ![Stress and muscle-freshness analytics](website/screens/stress_analytics.png) | ![Exercise catalog](website/screens/exercise_catalog.png) |

| Running | Customization |
|:---:|:---:|
| ![Running tab](docs/screenshots/running.png) | ![Accent and appearance customization](website/screens/customization.png) |

---

## Features

### Home
- Year activity grid for **Weights**, **Running**, and **Both**
- Workout count and day-of-year on the year card
- **Today’s stress** under the year overview
- Next workout from your active program, or start an empty session

### Workout logging
- Custom number pad (no system keyboard) with rest timer
- **RIR** on the reps keypad, with an in-session explainer
- Planned vs logged sets (`X out of Y sets done`)
- Edit a logged set’s weight, reps, and RIR without adding a new set
- Plate calculator for barbell and functional-trainer lifts
- Exercise history and estimated **1RM** per movement

### Programs
- Multi-day programs with a rotating next workout
- Sets per exercise while building a day
- Overview after you tap Done: planned sets, muscle breakdown, and split notes
- Import a program JSON from the desktop builder via Workout → Programs → Import

### Learn
- Core movement categories
- Key muscle groups
- More strength patterns
- Related muscles and patterns as separate cards you can tap through

### Info
- Today’s stress and 7-day trend
- 7-day tonnage and reps (totals and per muscle)
- Volume, 1RM, engagement, and intensity charts
- Searchable exercise history
- Sections you can hide from Settings

### Running
- Reads running, walking, hiking, and cycling from **Apple Health**
- Filters, pace and heart-rate charts, route map when GPS exists

### Widgets
- **Year** — small, medium, and large year-in-pixels views
- **Today’s stress** — small and medium
- **Next workout** — small

### Settings
- Custom accent and appearance (including a custom background color)
- Light, dark, or system appearance
- kg/lb and km/mi
- Body weight log synced with Health
- Optional write of finished strength sessions to Apple Health (Traditional Strength Training)
- Export / import JSON backup
- Info-page visibility toggles

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData |
| Charts | Swift Charts |
| Maps | MapKit |
| Health | HealthKit (cardio read; body mass read/write; optional strength workout write) |
| Home screen | WidgetKit |

---

## Testing

Three independent CI jobs run on every push and PR (see the badge above):

| Job | What it covers | Run locally |
|---|---|---|
| iOS unit tests | Analytics math (`WorkoutApp/Analytics/`), JSON codable round-trips, SwiftData integration, iOS↔web JSON contract | `xcodebuild -project WorkoutApp.xcodeproj -scheme WorkoutApp -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:WorkoutAppTests` |
| program-builder unit tests | Muscle-group analysis, equipment/pattern inference, JSON formatting (Vitest + jsdom) | `cd program-builder && npm ci && npm test` |
| Schema-compat check | Validates the shared `contract/program-template.schema.json` fixture with ajv | `cd program-builder && npm run schema:check` |

The `contract/` directory holds the JSON Schema and fixture shared between `WorkoutApp/Services/ProgramTemplateService.swift` and the web builder's export/import — both test suites decode the same fixture, so a schema drift on either side fails CI.

---

## App Store

- Privacy strings for HealthKit are in `Info.plist`
- `ITSAppUsesNonExemptEncryption` is `false`
- Strength sessions stay on-device unless the user turns on **Write finished workouts to Apple Health**
- Cardio workouts from Health are read-only
- Replace `com.local.WorkoutApp` with your production bundle ID and App Icon before submit

---

## Program Builder (web)

Desktop site to assemble rotating programs from the same exercise catalog (names and photos). Overview analysis covers 20 muscles, with views for **Upper / lower**, **Push / pull / legs**, and **Antagonists**. Export JSON and import it in the app via Workout → Programs → Import.

### **Live site:** *[Program Builder](https://program-builder-mu.vercel.app/)*

### Run locally

```bash
cd program-builder && python3 -m http.server
```

Then open the local URL (default `http://127.0.0.1:8000/`).

### Deploy

Static files live in `program-builder/`. On Vercel, set the project **Root Directory** to `program-builder`.

### Screenshots

#### Builder
![Program Builder workspace](docs/screenshots/program-builder.png) 

#### Exercise picker
![Exercise picker](docs/screenshots/program-builder-picker.png)

| Overview | Antagonists |
|:---:|:---:|
| ![Push / pull / legs overview](docs/screenshots/program-builder-overview.png) | ![Antagonists overview](docs/screenshots/program-builder-antagonists.png) |
