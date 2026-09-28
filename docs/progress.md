# myTwin: progress summary and next steps

*Written 28 September 2026. RevenueCat Shipaton 2026 (Next Gen Award) deadline:
30 September, 11:45 PM PDT.*

## 1. Where things stand

myTwin is an iOS app (SwiftUI, iOS 26, iPhone 15 Pro as the target device) that reads sleep,
heart rate and steps from Apple Health, predicts whether today will run above or below *your
own* normal, and shows it through **Dash**, a 3D character built in Blender. It then plans
around that reading: suggestions in your free time, Rescue my day, step-goal walks and
tomorrow's goals. **myTwin Pro** is sold through RevenueCat.

| | |
|---|---|
| Commits | 68 on `main`, all pushed to [github.com/aditya-baniya-ai/myTwin](https://github.com/aditya-baniya-ai/myTwin) |
| Code | about 10,000 lines of Swift in the app and widget, 1,000 lines of tests |
| Tests | 67 unit tests and 6 UI tests; the last two full runs passed completely |
| On the phone | The latest build is installed on the iPhone 15 Pro (free Apple account: it expires around **3 October**) |
| Repository | Public, MIT licence, README written for the judges with screenshots and animations |

## 2. What was built, by area

### Dash, the 3D twin
- Modelled, rigged and animated in Blender: 9 animation clips on one timeline, 16 face shapes,
  a baked normal map for skin, hair and cloth. Exported as a single USDZ and run in RealityKit.
- **Four energy states**, each with its own idle loop and glow colour: Energetic (green),
  Normal (blue), Tired (orange), Exhausted (pink).
- **Gestures:** wave, jump, stretch, yawn, doze, played on his own to suit his mood.
- **See all of Dash** showcase screen with every state and gesture.
- Grows bigger once the check-in card is answered; waves when he speaks up.
- The **welcome screen** shows the live 3D Dash in his energetic state, waving hello.
- README has looping animations (greeting, jump, yawn, doze) recorded from the app.

### The energy prediction
- A small ridge-regression model on five sleep and resting-heart-rate features, relative to
  your recent baseline. It needs today's sleep plus seven usable nights in the last 14 days.
- Honest about its limits: it predicts **direction, not a number**. On PMData (16 people,
  1,747 days) within-person correlation improved from -0.054 to +0.103 (fatigue) and +0.051
  to +0.124 (readiness). The percentage and the hourly curve are labelled as illustrations.
- A second dataset (LifeSnaps, 71 people) gave no usable signal; written up in `ml/README.md`.
- Learns each person's own weights from their check-ins, on the device.

### The five (now six) pages
1. **Dash:** the twin, today's verdict, a greeting that knows the time and your next event,
   the "How do you feel right now?" check-in (hides once answered, returns in the afternoon
   and evening), Rescue my day, "Did that help?" and "Up next", and from 5 PM a **Plan
   tomorrow** card.
2. **Predictions:** the hour-by-hour forecast with peak focus and likely dip (Pro), the last
   7 days, "Your week" told as a story, and "You often ask".
3. **Activity:** steps, active energy, sleep and weight rings with goals, heart and body
   metrics (only those Apple Health actually holds), workouts, and the **step-goal pace card**.
4. **Plan:** today's calendar with suggestions in the gaps (workout, easy task, nap, last
   coffee), swipe to add or dismiss, a Week view, and Rescue my day.
5. **Tomorrow (new):** write tomorrow's goals; tick off today's; carry the rest over; Plan my
   day tomorrow (Pro).
6. **You:** preferences (Make it yours), Dash's voice, Pro and Customer Center, connections
   (Apple Health, Calendar, Gemini), and "Try the demo".

### Planning features
- **Suggestions** in free time, at most four a day: a workout in your strongest free hour,
  "Prepare for tomorrow" after 5 PM, a nap at the dip (not too close to bedtime), and the last
  coffee that still clears before bed. Dismissed three times, they stop coming back.
- **Rescue my day (Pro):** swap a planned session or add a new flexible activity, choose the
  time yourself or let Dash find the next free gap, preview before and after, confirm, and
  undo from the dashboard. Only activities myTwin created can change.
- **Did that help? then Up next:** after an accepted activity ends, one question (Better /
  Same / Worse / Skipped). Answering replaces it with the next event and a one-line tip based
  on the kind of event and your energy then.
- **Step-goal walks (everyone):** every couple of hours it projects today's steps (steps so far
  plus your usual steps from this hour on, the median of the last three weeks). If you'll fall
  short, a 5 or 10-minute walk goes into the next free slot on your calendar with a
  notification. At most every 2 hours, 3 walks a day, one waiting at a time, never at night.
- **Tomorrow's goals:** one goal per line; the app reads a length ("2 hrs"), a time ("at 7pm")
  or a part of the day ("morning"), and whether it's work or personal. Everyone gets the
  nightly "Did you finish today's goals?" and carry-over. **Plan my day tomorrow (Pro)** puts
  goals into tomorrow's free time (fixed times first, work in your strongest hours, personal
  later), as calendar events with a 10-minute reminder, plus a morning notification.
- **Bedtime event:** a repeating "Bedtime" event at your bedtime, moved when you change it,
  removed when you turn it off.
- **Week recap:** your best and hardest day with the reason (sleep, resting heart rate, deep
  sleep versus your own averages), and one pattern across the week.

### Talking to Dash
- **Wake word "twin"** (and near-misses like *tween*, *twain*), or tap Dash to talk.
- **Recording bar** when you tap Dash: discard, a timer, dots that flow and rise with your
  voice, and a send button. Only your tap sends.
- **Fixed:** the app used to send only the first word or two. The speech recogniser runs a few
  seconds behind and delivers in bursts, so the send now waits for it to finish everything up
  to your tap (about 0.1 s on the iPhone).
- **Answers** from Apple's on-device model, or Gemini (Pro, with consent) when online, with
  tools that read your calendar, health summary, plan and week.
- **Voices:** a picker with previews for iPhone voices (offline) and Gemini voices (Pro).
  Fixed a bug where a female voice slipped through, and Gemini cutting itself off mid-answer.
- **Dash speaks up on his own** on any page and when you return to the app: a low-energy event
  coming up, a dip with nothing booked, a suggestion about to start, long sitting, and the
  week's story on Sunday. Once a day per topic, 90 minutes apart, never in quiet hours.
- **"You often ask":** your repeated questions over the last two weeks as shortcuts. Free sees
  them locked; Pro sees Dash's latest answer under each.

### Guest mode and onboarding
- **Welcome screen:** *Continue as a guest* or *Continue as a user*.
- **Guest:** *Continue with Pro* or *Continue without Pro*. A full fictional user ("Alex")
  with a week of calendar, sleep, heart rate, steps, workouts, weight, goals and questions.
  Every demo page has a Free/Pro switch and **Use my account**. Nothing touches real data.
- **User:** name and age, then connect Apple Health and Calendar (or skip).
- **Try the demo** from the You page at any time.
- **Fixed crash:** opening the demo from your own screen crashed on the phone, because two
  voice systems fought over the microphone. The app now shares one.

### Free and Pro (RevenueCat)
- RevenueCat SDK with the `mytwin_pro` entitlement, live updates through `customerInfoStream`,
  the paywall designed in the RevenueCat dashboard (Paywalls V2) with a hand-written fallback,
  Customer Center for managing and restoring, and a debug "Reset to free" row.
- Plans: Monthly $9.99, Yearly $79.99, Lifetime $99.99. Uses the **Test Store** key (simulated
  purchases, no real money).
- Pro unlocks the forecast, suggestions, Rescue my day, answers on "You often ask", Gemini and
  its voices, and Plan my day tomorrow. Free keeps Dash, check-ins, week story, calendar,
  notifications, widget, on-device chat, step walks and writing goals.

### Works while the app is closed
- A HealthKit observer wakes the app when sleep, resting heart rate, weight or steps arrive.
- Home Screen widget (small and medium).
- Notifications: morning briefing, event heads-ups, bedtime nudge, step walks, goals morning
  and night.

### README and documentation
- A judges' section: how to open the demo in 2 minutes on a Simulator (no keys or signing) or
  their own iPhone, and what works where.
- Every feature with who it helps, and screenshots; Free vs Pro table; how it works diagram;
  a 2-minute guided tour; honest limits; build steps.
- `docs/verification.md` for test results; this file for progress.

## 3. Testing

| What | Result |
|---|---|
| Unit tests (67) | Planner, rescue, week story, nudges, questions, demo mode, step pace, step check, goals, bedtime, tips, loudness, daily support. All pass, run twice. |
| UI tests (6) | Onboarding (guest Free, guest Pro, user setup), sample-day rescue and preferences, tomorrow's goals planned. All pass, run twice. |
| Simulator by hand | Every new screen checked with screenshots before each commit. |
| iPhone by hand | Voice sending the full question, the recording bar, the demo crash fix. |

The UI tests have been timing-sensitive; they now wait for sheets and scroll in short steps.
The test runner sometimes hangs after finishing, which is a known Xcode issue, not an app bug.

## 4. Not yet verified or known limits

- **On the phone over a real day:** the step check waking in the background, the evening goals
  notification, the morning goals list, and walks at the right moment. Garmin syncs steps in
  batches, so the step check can run late.
- **Chat and voice answers in the demo** on the phone. The Simulator can't run Apple's model.
  After the last phone test the result was reported as "Something else" with no detail.
- **See all of Dash:** the gesture buttons didn't visibly animate on the Simulator, while the
  home-screen Dash animates fine. Not yet checked on the phone.
- **Reading goals** uses text rules. Clear lines work; number words ("two hours") and "p.m."
  are not read yet, and loose sentences may not split well.
- **Suggestions feel sparse on busy days:** a gentle stretch counts as the day's workout, and
  after 5 PM there's only "Prepare for tomorrow".
- **Paywall links:** Terms and Privacy on the RevenueCat dashboard paywall point to example.com.
- The nine images in `assets/Dash/readme_frames/` are all the same T-pose; they're unused.
- GitHub shows "claude" as a contributor because of the co-author line in commits.

## 5. Next steps

### Before the deadline (30 Sept, 11:45 PM PDT)
1. **Rotate the Gemini API key** (it appeared in an earlier session's output) and put the new
   one only in `Config/Secrets.xcconfig`.
2. **Ask the organisers** whether a RevenueCat Test Store build is acceptable without the paid
   Apple Developer Program.
3. **Replace the example.com Terms and Privacy links** in the RevenueCat paywall.
4. **Test on the phone:** open the demo, chat with Dash, tap See all of Dash → Jump, write goals
   and plan them, and set a step goal. Report anything odd with a screenshot.
5. **Record the demo video** for the submission, following the README's 2-minute tour.
6. **Submit** with the repo link, the video and the RevenueCat project details.

### Small, useful improvements (hours, not days)
- **Speak your goals (in progress):** a mic on the goals box using Dash's recording bar, with
  Apple's on-device model splitting speech into goals. Tested on the Mac: the split is
  reliable, but one wording dropped details ("two hours in the morning") and a stricter one
  invented goals once. Next: use the first wording, teach the parser number words and "p.m.",
  and add a fallback that splits on sentences.
- **Hide the tab bar while typing:** it currently rides up above the keyboard.
- **Suggestions:** count stretches and walks as light movement, and add evening options (a
  short walk after dinner, wind-down).
- **Delete the unused T-pose images** in `assets/Dash/readme_frames/`.
- **Check and fix See all of Dash** gestures once seen on the phone.

### After the hackathon
- Paid Apple Developer Program: Sign in with Apple, TestFlight, App Store key (`appl_…`)
  instead of the Test Store, and a signing that doesn't expire weekly.
- Optional accounts (Supabase: email, Google, Apple) so Pro follows you across devices.
- Use Apple's model (or Gemini) for smarter goal reading and suggestions.
- Better step predictions from more history and weekday patterns.
- An Android version would need its own app; the backend plan in the design notes works for both.

## 6. Keep in mind

- `Config/Secrets.xcconfig` holds the Gemini key and is ignored by git. Never commit it.
- The RevenueCat **public** Test Store key in `Config/Base.xcconfig` is meant to be committed.
- The app install on the iPhone expires about 7 days after each install (free Apple account).
- UI screenshots in the README come from the demo, so they contain no personal data.
