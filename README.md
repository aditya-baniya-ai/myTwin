# myTwin

An iOS app with a 3D twin who reads your health data, works out when your energy will
peak and dip today, and puts things in the gaps in your calendar — a workout in your
strongest free hour, a nap at the dip, the last coffee that still clears before bed.

Built for the [RevenueCat Shipaton 2026](https://www.shipaton.com) Next Gen Award.

## What it does

**Reads** sleep, resting heart rate, heart rate variability, steps, active energy,
workouts and weight from Apple Health, plus today's events from your calendar.

![Dash in his four energy states](assets/Dash/renders/Dash_States.png)

**Predicts** whether today is better or worse than *your* normal — not an absolute score.
The model is your own 14-day running average plus a small ridge regression on three sleep
features. It needs about two weeks of your data before it says anything at all.

**Plans** around what it finds: it walks the gaps between your real events in 15-minute
steps and suggests what fits, avoiding what you've already dismissed three times.

**Talks**, by tapping the avatar. Speech is transcribed on device with `SpeechAnalyzer`.
Answers come from Gemini when you're online and you've allowed it, and from Apple's
on-device Foundation Models when you're not.

**Keeps working while closed.** A HealthKit observer wakes the app in the background,
recomputes, updates the Home Screen widget, and schedules the day's notifications: a
morning briefing, a heads-up ten minutes before each event, and a bedtime nudge.

## Honest limits

The model predicts **direction, not a number**. Measured with leave-one-person-out
evaluation on [PMData](https://datasets.simula.no/pmdata/) (16 people, 1,747 labelled days):

| Target | Within-person correlation | People improved | Wilcoxon p |
|---|---|---|---|
| Fatigue (1–5) | −0.054 → **+0.128** | 12/16 | 0.008 |
| Readiness (0–10) | +0.051 → **+0.188** | 14/16 | 0.001 |

Absolute error barely moves (readiness MAE 1.152 → 1.151), which is exactly why the app
talks about "better or worse than your normal" and never shows a score out of ten.

A second dataset, LifeSnaps (71 people), gave no usable signal at all — within a person,
tiredness tracked the hour of the day and nothing else. That negative result, and why
LightGBM lost to a five-weight ridge, are written up in [`ml/README.md`](ml/README.md).

## RevenueCat

Free covers what today already is: the charge, today's numbers, your own calendar events
and all the notifications. **myTwin Pro** adds what the app works out for you — the
hour-by-hour forecast, the suggestions that fill your free time, and Gemini's answers
(without Pro, the twin still replies from the on-device model).

- `Subscription.swift` wraps the SDK: `configure`, `customerInfo()`, `offerings()`,
  `purchase(package:)`, `restorePurchases()`, and `customerInfoStream` so an unlock lands
  without a restart.
- Gating is driven by the `mytwin_pro` entitlement. Locked features show a `LockedCard`
  that opens the paywall in place, and the sheet closes itself on success, returning you
  to the page you came from.
- `ProPaywall` prefers the paywall designed in the RevenueCat dashboard and falls back to
  a hand-written SwiftUI one when the offering has none.
- The **Customer Center** (`RevenueCatUI.CustomerCenterView`) handles managing and
  restoring a plan, on the You tab.

Three plans come from the dashboard: monthly, yearly and lifetime.

> This repository is configured with a RevenueCat **Test Store** key. Purchases are
> simulated, no money moves, and Apple rejects Test Store keys at App Review. Swapping in
> a platform (`appl_…`) key is a one-line change in `Config/Base.xcconfig`; no other code
> changes.

## Building it

Requires Xcode 26 and iOS 26. The avatar uses RealityKit, so the 3D scene needs a device;
everything else runs in the Simulator.

```bash
git clone https://github.com/aditya-baniya-ai/myTwin.git
open myTwin/myTwin.xcodeproj
```

It builds and runs as-is: the RevenueCat key is committed (public keys are meant to be),
so the paywall works out of the box.

Gemini is optional. Without a key the app never calls it and answers on device instead.
To enable it, create `Config/Secrets.xcconfig` — git-ignored, never commit it:

```
GEMINI_API_KEY = your-key-here
```

## Layout

| Path | What's in it |
|---|---|
| `myTwin/` | The app: five tabs — the twin, predictions, activity, the plan, you |
| `myTwin/Pro/` | RevenueCat: the subscription wrapper and the paywall |
| `myTwin/Avatar/` | The RealityKit twin, lit by how charged you are |
| `myTwin/Gemini/` | The Live API client and the consent flow |
| `myTwin/Dashboard/` | Cards, the smart calendar, the day planner |
| `myTwinWidget/` | The Home Screen widget |
| `Shared/` | Code and the model shared with the widget |
| `ml/` | Training, evaluation, and what didn't work |

Training data is not in this repository: PMData is CC BY-NC and belongs to its authors.
`ml/download_pmdata.py` fetches it.

## Licence

MIT — see [LICENSE](LICENSE).
