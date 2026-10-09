# Forge v7 — issues found and fixed

Branch: `v7-polish` (based on v6, commit 79e0c85). 41 issues fixed across 13 files.

**Schema:** one additive change only. `LoggedSet.exerciseOrder: Int?` (optional, so existing stores migrate with no data loss). Nothing renamed, nothing retyped.

**Verification:** every Swift file was syntax-parsed after editing. It has NOT been compiled or type-checked yet — the first Xcode build on the Mac is the real check.

## Workout logging — WorkoutFlowView.swift

1. **Back swipe threw away the whole workout.** The logging screen had the normal back button and swipe-back gesture, which discarded every set with no warning. Fix: back button hidden; Cancel (with confirmation) is the only way out.
2. **Duplicate workouts.** After Finish, the summary was pushed on top of the still-filled logging screen. Back from the summary, then Finish again, saved the same workout twice. Fix: finishing replaces the logging screen with the summary.
3. **Duplicate on a failed save.** If `context.save()` threw, the new session stayed inserted in the context, so a retry inserted a second copy. Fix: `context.rollback()` on failure.
4. **Keyboard Done dead on cardio fields.** Cardio minutes and miles weren't bound to the shared focus state, so the one Done button did nothing for them. Fix: added `.cardioMinutes` and `.cardioMiles` cases to `LoggingField`. Still ONE shared `@FocusState` and ONE keyboard toolbar.
5. **Typos saved as 0 lb.** A weight like `185.5.5` failed to parse and was silently saved as 0 lb; bad cardio minutes were silently dropped. Fix: unreadable numbers now block saving with an alert naming the exact set.
6. **Half-filled rows vanished silently.** A set with a weight but no reps was dropped without a word. Fix: the Finish confirmation now says how many sets or cardio bouts will be left out.
7. **Cardio in the strength picker.** Jump squats, box jumps, etc. could be added as weight × reps sets. Fix: the strength picker lists only non-cardio moves.
8. **Exercises listed twice.** Moves with two primary muscles (dips) appeared in both sections. Fix: listed once under the first primary; the caption names the other.
9. **No confirmation before removing work.** One tap on the trash icon deleted an exercise and all its typed sets. Fix: asks first when the row has data; empty rows still remove instantly.
10. **Couldn't un-add a mis-tapped exercise.** The picker checkmark looked like a toggle but did nothing. Fix: tapping a checked, still-empty exercise removes it.
11. **Unfinished workouts lost when iOS closes the app.** Switching to music or the camera at the gym can get Forge killed, losing every set. Fix: the logging screen autosaves to a small JSON file per profile in Application Support (`WorkoutDraftStore`) on every edit. The Workout tab shows a Resume / Discard card, and the app opens on that tab when a draft exists. The draft is cleared on Finish or Cancel. It is a plain file, not a SwiftData model, and UserDefaults still holds only the active profile ID.
12. **Possible out-of-range crash when deleting a set.** Set rows were bound with array bindings while rows were being removed. Fix: rows bind by set ID.
13. **Live volume didn't match saved volume.** The card skipped blank-weight sets that saving counted as bodyweight (0 lb). Fix: both use the same rule.
14. **Cancel on an empty workout asked "Discard?"** Fix: nothing to lose, so it just leaves.

## Exercise order — Models.swift, TrainingMath.swift, SummaryGenerator.swift, HistoryView.swift, DataBackup.swift

15. **Exercises reshuffled in the recap and History.** SwiftData does not keep the order of a to-many relationship, so `session.sets` came back in a different order after relaunch. Fix: new optional `LoggedSet.exerciseOrder`, set at save time. `TrainingMath.exerciseGroups(sets:)` sorts by it. Sets saved before v7 (nil) fall back to alphabetical so they at least stay stable.

## History — HistoryView.swift

16. **Wrong cardio shown on a workout.** Session detail showed every cardio entry from the same calendar day, so two workouts in one day showed each other's cardio. Fix: cardio pairs with its workout by start time (`TrainingMath.cardio(for:in:)`, ±2 s to survive backup rounding).
17. **No way to delete a mistaken workout.** Fix: swipe left → confirmation → deletes the session, its sets, and its paired cardio. Rolls back if the save fails.
18. **Cardio-only workouts read "0 exercises · 0 lb".** Fix: the row shows cardio minutes, plus the start time.
19. **Wrong empty message.** The Mon–Sun "This week" section said "last 7 days". Fix: "since Monday". The Insights section now says it uses the last 7 days.
20. **Bodyweight sets displayed "× 0 lb".** Fix: shown as "bodyweight".

## Today — DashboardView.swift

21. **Number pads couldn't be closed.** Decimal and number pads have no return key, so the keyboard stuck open on Today, Profile, Onboarding, and Add Profile. Fix: dragging the page dismisses it, and Add dismisses it on Today. No new keyboard toolbars were added, so the workout screen's single Done button is the only one.
22. **Food Add did nothing silently.** With no name, tapping Add did nothing; bad numbers were saved as 0. Fix: inline error messages.
23. **Typos were permanent.** A wrong water amount or food entry couldn't be removed. Fix: "Undo N oz" for the last water entry; an ✕ on each of today's food entries.
24. **Calories were logged but never shown.** Fix: today's kcal total appears next to protein.
25. **"This week" label on a rolling window.** The muscle figure was labeled "this week" but used a rolling 7 days. Fix: label now says "last 7 days".
26. **Water sanity check ignored units.** The limit was 10,000 in either unit. Fix: capped at 256 oz per entry after the mL conversion.

## Profile — ProfileView.swift

27. **PIN often never saved.** The PIN field sat below the Save button, so it was easy to type a PIN and never save it. Fix: moved above Save.
28. **Stale "Saved." and swallowed errors.** "Saved." stayed after further edits, and save errors were ignored (`try?`). Fix: the message clears on any edit; failures show the error and roll back.
29. **Success color by string comparison.** Green/red was decided by comparing the message text to "Saved.". Fix: an explicit error flag.

## Profile switcher — ProfileSwitcherView.swift

30. **Nested NavigationStack.** The switcher wrapped itself in a second NavigationStack while being pushed inside Profile's stack, which glitches the nav bar and back button. Fix: removed.
31. **PIN prompt rough edges.** No Cancel, no autofocus, and a wrong PIN left the digits in the field. Fix: Cancel button, autofocus, checks automatically at 4 digits, clears on a wrong PIN.
32. **Tapping the current profile did nothing useful.** Fix: it just goes back.
33. **Add Profile swallowed save errors.** Fix: they're shown and rolled back.

## Backup & restore — DataBackup.swift

34. **Restore could crash on unique IDs.** It deleted every row and re-inserted rows with the same `@Attribute(.unique)` IDs in a single save. Fix: two phases, wipe-and-save then insert-and-save, each rolling back on failure. If phase 2 fails, the error says to rerun the restore with the same file.
35. **Region-dependent file names.** The backup file-name date formatter didn't pin a locale. Fix: `en_US_POSIX`.
36. **Backups didn't carry the new field.** Fix: backups now include `exerciseOrder` as an optional key. Old backups still restore, and `schemaVersion` stays 1.

## App-wide

37. **Hardcoded colors broke the theme rule.** `.red`, `.green`, `.orange`, `.blue`, `Color.gray`, `Color(.secondarySystemBackground)`, and the SceneKit `UIColor`s were scattered around. Fix: all moved into `ForgeTheme` (`card`, `track`, `success`, `danger`, `warning`, `info`, `sceneBackground`, figure greys, `voltGlow()`). A grep for color literals outside ForgeTheme.swift returns nothing.
38. **Comma decimals rejected.** Regions where the decimal pad shows "," couldn't enter numbers. Fix: `ForgeInput.decimal()` accepts both and is used on every numeric field.
39. **Onboarding swallowed save errors.** Fix: shown and rolled back, with sane bounds on height and weight.
40. **3D figure did extra work.** Body3DView rewrote SceneKit materials on every SwiftUI re-render. Fix: only when the training data changes; the glow is applied on first draw; volt glow uses the same RGB as `ForgeTheme.volt`.
41. **Contradictory water comment.** The TrainingMath water comment described ⅔ oz per lb while the code returns a flat 128 oz. Fix: the comment matches the code.

## Small polish (no behavior risk)

- Elapsed-time clock in the logging screen's nav bar.
- New sets prefill the previous set's weight.
- Exercise instructions sit behind an ⓘ button to cut clutter.
- Picker search matches muscle names ("chest", "quads") and shows an empty state.
- The summary shows the 3D figure and stat tiles before the long recap.
- Calories are marked "~" as an estimate.
- The volt button dims when disabled.
- Numbers animate on change.
- Today is highlighted on the week bars.
- Recap text is selectable.

## Rules for the next person editing Forge

1. Every model has `ownerID`, and every query filters by the active profile.
2. Schema changes are additive only: new optional or defaulted properties, or new `@Model` types. Never rename or retype a property.
3. All colors come from ForgeTheme.swift.
4. The workout screen keeps ONE `@FocusState` (`LoggingField`) and ONE keyboard toolbar. New fields there get a `LoggingField` case, never their own toolbar.
5. Cardio entries are stamped with their session's `startTime`; that is how History pairs them. Keep it that way.
6. Parse typed numbers with `ForgeInput`, never `Double(text)` directly.
7. A screen pushed onto an existing NavigationStack must not wrap itself in another NavigationStack.
8. On any failed `context.save()`, call `context.rollback()` and tell the user.
