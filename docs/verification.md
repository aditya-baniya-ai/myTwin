# Verification and demo handoff

Branch: `test-branch` (Git branch names cannot contain spaces).
Base commit: `001a7b174a1b75499f9100508691313a6e0ca884`.

## Implemented

1. Rescue my day: activity/duration choice, calendar-gap preview, explicit confirmation,
   ownership and conflict checks, and dashboard undo. The first rescue is free; further
   rescues require Pro. Only app-owned, unchanged, nonrecurring activities can be replaced.
2. Fictional sample day, available from onboarding or You, plus activity, equipment,
   duration, bedtime, optional goal and reminder preferences. Manual energy check-ins
   work without a watch. Sample changes stay in memory.
3. Why this plan: measured sleep, baseline coverage, estimated direction, uncertainty,
   and a self-report correction. Hourly percentages are explicitly illustrative.
4. Better / Same / Worse / skipped activity feedback, persistent personal history,
   and suggestions supported by repeated feedback. This is an association, not proof
   that an activity caused a change.
5. Dash share cards: rendered PNG, preview, optional title/time, native share sheet,
   and SAMPLE DAY marking for fictional content.

## Corrections

- Restored HealthManager query methods missing from the working file, preserving the
  newly added meal-logging method.
- Clipped planner gaps to bedtime, avoided overlaps between suggested activities,
  and handled forecast requests after bedtime.
- Aligned inference with the exported seven-night minimum and 14-calendar-day window.
- Removed fixed bodybuilding/meal/weight targets from the new planning flow.
- Gated premium plan context and Gemini fallback, exposed purchase retry and
  voice/model availability status.
- Calendar writes refresh both day and week views. Rescue writes recheck conflicts
  and event ownership; undo refuses to overwrite externally changed events.
- Reminder preferences and quiet hours replace automatic generic repeating reminders;
  reminders use one-shot dates and tomorrow's morning message asks for a fresh check-in.
- Exported training-only imputation medians and made Swift inference use them.
  Re-evaluated the five-feature model, synchronized app/widget JSON, and corrected
  outdated research claims and reproduction instructions.
- Added shared Xcode scheme, unit tests and UI tests to the repository.

## Automated verification

**Final result (September 27, 2026): 14/14 tests passed — 12 unit tests and
2 end-to-end sample-day UI tests. Final device Release build passed.**

The planner test includes 90 start-time combinations and checks both event and
suggestion overlaps. UI checks cover saving/reopening preferences, outcome feedback,
private share-card rendering, the native share sheet, rescue preview/confirmation/undo,
and the explanation/self-report correction flow.

Final test bundle: `/tmp/mytwin-tests-verified.xcresult`.
Test log: `/tmp/mytwin-tests-verified.log`.
Final Release log: `/tmp/mytwin-release-verified.log`.
Xcode result bundles and logs remain under `/tmp` on this machine. The initial expanded run exposed incorrect accessibility selectors (a toggle
container and a share-sheet cell) and a test-worker startup timeout; these were diagnosed
using XCTest attachments rather than counted as a passing run.

- Initial full run: 12 unit tests and rescue/explanation UI flow passed.
- Debug app and widget build: passed.
- Unsigned device Release app and widget build: passed; no archive/upload/signing performed.
- Python syntax checks: passed for `ml/`.
- Current `train_final.py` and `significance.py`: completed on the available local derived
  table, using the same evaluation pipeline.
- Historical `healthkit_only.py` and `window_test.py`: completed; these are separate
  experiments, not the shipped model's metrics.
- Shared/exported JSON: identical, 24 hourly values, five finite coefficients per target,
  exported imputation medians and 7/14 thresholds verified.

## Checks that still need a device or external setup

These are not covered by fictional sample-mode UI tests:

- Real Apple Health permission denial/revocation, Watch data import, background delivery,
  speech recognition, wake phrase, Apple Intelligence and live Gemini audio.
- Saving/replacing/undoing activities in a real writable EventKit calendar, including
  another app changing the event while a preview is open.
- Notification delivery while the app is closed and quiet-hour behavior on a real device.
- RevenueCat purchase, restore, cancellation and expired-entitlement flows with your
  configured store products. This repository currently uses a RevenueCat Test Store key.
- Signed archive, TestFlight/App Store release, and hackathon submission assets.
- A fresh raw-data download/rebuild: local raw PMData and LifeSnaps files were absent.
  Research validation does not establish personal or clinical accuracy; see `ml/README.md`.

## Two-minute demo path

Open **Try a sample day**, show the fictional-data label, then **Why this plan?**.
Choose how you feel, open **Rescue my day**, preview the shorter activity, confirm and
show **Undo change**. Open **Make it yours** to demonstrate preferences. Mark the
sample walk **Better**, then **Share my moment** to show the private card and native
share sheet. Exit sample mode to show the real connection and Pro screens.

## Re-run

```sh
xcodebuild -project myTwin.xcodeproj -scheme myTwin \
  -destination 'platform=iOS Simulator,name=myTwin Review' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
python3 ml/train_final.py
python3 ml/significance.py
python3 -m compileall -q ml
```

Use an available simulator name or ID on another machine. The Python runs need the
local derived CSV and dependencies documented in `ml/README.md`.

Research runtime used: Python 3.10.11, NumPy 1.26.4, pandas 2.2.3,
SciPy 1.15.1 and scikit-learn 1.6.1. Current model SHA-256:
`f36682db8e38dcc84e7772cdf12a37822948d803dfcf9a4eabde44470f1a2b55`.
