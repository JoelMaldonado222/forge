# ⚡ Forge

**Forge** is a native iOS gym-tracking app. Log workouts with per-set weight and reps, track water and food, and watch the muscles you trained light up on an interactive 3D body map.

Built with SwiftUI, SwiftData, and SceneKit. Zero third-party dependencies. All data stays on your device.

## Features

- **Workout logging** — start a session and add exercises as you go; every set gets its own weight × reps (set 1: 135 × 10, set 2: 185 × 8…)
- **Bodyweight assist** — pull-ups, dips, push-ups and more one-tap fill your current body weight, and stay correct as your weight changes
- **3D muscle map** — trained muscles glow volt on an anatomical figure (chest bright on bench day, shoulders/triceps at half); drag to rotate, pinch to zoom
- **Water & fuel tracking** — daily water ring against a 1-gallon target, protein and calorie logging with oz/mL input
- **7-day volume & insights** — total weight lifted, per-muscle volume bars, estimated 1RMs, cardio minutes
- **Backup & restore** — export everything to a versioned JSON file; restore anytime with one tap
- **Multi-profile** — separate profiles with optional PINs; workouts, water, and food never mix between profiles
- **Private by design** — on-device SwiftData store, no account, no cloud, no tracking

## Getting started

Requirements: Xcode 16+ and an iPhone running iOS 17+.

1. Clone this repo
2. Open `Forge.xcodeproj`
3. Under **Signing & Capabilities**, select your Team
4. Pick your iPhone and hit **Run**

> With free Apple provisioning the app expires every 7 days — just press Run again to refresh it. Re-installing preserves your data. Deleting the app deletes its data, so keep a safety copy via **Profile → Back up & restore**.

## How it works

- **SwiftUI** for all UI, including a volt-electric athletic theme (`ForgeTheme.swift`)
- **SwiftData** (local SQLite) for persistence — schema changes are additive-only, so app updates never wipe training history
- **SceneKit** for the 3D muscle figure; per-muscle materials glow based on trained volume
- `TrainingMath.swift` holds the training formulas (Epley 1RM, volume load, protein/water targets) with their evidence notes
- No packages, no Podfile, no network calls

## License

MIT — see [LICENSE](LICENSE).
