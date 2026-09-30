<div align="center">

# myTwin

### Meet Dash. Understand your energy. Make a plan you can actually follow.

<img src="assets/Dash/videos/dash_wave.gif" width="200" alt="Dash waving hello"/>

![iOS 26](https://img.shields.io/badge/iOS-26-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![RealityKit](https://img.shields.io/badge/3D-RealityKit-purple)
![RevenueCat](https://img.shields.io/badge/Subscriptions-RevenueCat-F25A5A)
![MIT](https://img.shields.io/badge/License-MIT-green)

Built for the RevenueCat Shipaton 2026 · Next Gen Award

</div>

A full calendar does not tell you whether you have the energy for it. **myTwin helps you
plan your day around your sleep, activity and goals.**

Meet **Dash**, your animated 3D companion. He shows how your energy might change, helps you
make room for your goals and talks through your day with you. You can **speak or type**.

Start with Free for check-ins, activity, goals and your calendar. Pro adds energy forecasts,
automatic goal scheduling, **Rescue my day** and conversations with Dash using Gemini voice.

Energy forecasts are estimates, not medical advice or a measurement of your body's battery.

<p align="center">
  <img src="assets/screenshots/guide/demo-pro-dash.png" width="240" alt="Pro demo: Dash"/>
  <img src="assets/screenshots/guide/demo-pro-plan.png" width="240" alt="Pro demo: daily plan"/>
  <img src="assets/screenshots/guide/mentor.png" width="240" alt="Pro mentor: Gemini reply and voice or text controls"/>
</p>

## Start here

- [Try the five-minute demo](#judges-five-minute-walkthrough)
- [Build and run](#run-the-app)
- [Explore the features](#use-every-feature)
- [Compare Free and Pro](#free-versus-pro)
- [Use your own data](#set-up-your-own-account)
- [Set up Gemini and other services](#configure-integrations)
- [Need help?](#troubleshooting)

## Judges: five-minute walkthrough

Try the app with **Alex's fictional day**. You do not need a watch, personal health data
or a purchase. The demo is set at 2 PM so you can repeat the same walkthrough.

1. **Meet Dash.** [Run the app](#run-the-app), then choose **Continue as a guest → Continue with Pro**.
2. **See the day ahead.** Open **Predictions** to see the energy forecast, then **Plan** to see the schedule.
3. **Rescue a busy day.** Tap **Rescue my day → Preview my rescue → Confirm demo change**.
   See what moved, then try **Undo change**. Your real calendar is untouched.
4. **Plan tomorrow.** Open **Tomorrow**, write a goal and tap **Plan my day tomorrow**.
   Change expected sleep to explore how the outlook changes.
5. **Talk to Dash.** With [Gemini configured](#configure-integrations), tap
   **Start conversation** on Dash. Type on Simulator or speak on a supported iPhone.
   Try: “Which goal should I focus on first?”
6. **Compare Free and Pro.** Use the **Free / Pro** switch in the demo banner.
   Tap **Use my account** when you want to connect your own data.

**No Gemini key?** You can still try the other demo features. Only the Gemini conversation
needs a key, permission and internet access.

## Run the app

### Simulator: quickest route

You need a Mac with **Xcode 26 or later**, an **iOS 26 or later** Simulator and internet
access to download dependencies. There is no separate server to run.

```sh
git clone https://github.com/aditya-baniya-ai/myTwin.git
cd myTwin
open myTwin.xcodeproj
```

1. Wait for Xcode to resolve Swift Package Manager dependencies.
2. Select the **myTwin** scheme and an installed iPhone Simulator.
3. Press **⌘R**. Choose the guest route on the welcome screen.
4. For repeat demonstrations, open **Product → Scheme → Edit Scheme → Run → Arguments**.
   Add `--sample-day` for Pro or `--demo-free` for Free. Remove these arguments to use personal mode.

No private Gemini key is required for the visual demo. The repository includes a **public
RevenueCat Test Store SDK key**. Gemini chat and the mentor do require your own Gemini key.
Use a supported iPhone to try voice input and Apple’s on-device chat.

<details>
<summary>Running on an iPhone and Simulator limitations</summary>

| Capability | Simulator | Supported iPhone |
|---|---|---|
| Guest Free/Pro, Dash, calendar, goals, Rescue, settings | Yes | Yes |
| Typed Gemini replies and mentor interface | With key, consent and internet | With key, consent and internet |
| Voice input and hands-free reply timing | Not supported in the tested Simulator | Microphone/speech permission and supported language required |
| Apple Foundation Models answers | Unavailable in the tested Simulator | Apple Intelligence support and model availability required |
| Your own Health data and wearable syncing | No real phone/watch records | With Health access and records from your sources |
| Home Screen widget / Live Activity | Previewable; device validation still matters | Subject to iOS settings and update scheduling |

### Your iPhone

1. Connect and unlock your iPhone; trust the Mac if prompted.
2. In Xcode's app and widget targets, choose your development **Team** and unique bundle IDs.
3. Match the **App Group** in both targets and `Shared/TwinState.swift`.
4. Preserve the app's HealthKit capability, privacy usage descriptions and widget extension.
   Let Xcode manage signing; capability/provisioning errors must be resolved for your team.
5. Select your iPhone and run. Enable **Developer Mode** and trust the development build if iOS asks.
6. Follow personal setup below, or open the guest demo first.

Apple's [device and Simulator running guide](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
explains the device/signing workflow. App Store distribution needs its own production signing,
store configuration and review; changing a key alone is not a release process.

</details>

## Guest demo: Free and Pro

Choose **Continue as a guest**, then pick Free or Pro. Switch between them in the demo banner.
Demo health records, goals and calendar events are fictional.

<details>
<summary>See the demo steps and Free / Pro screenshots</summary>

<p align="center">
  <img src="assets/screenshots/guide/welcome.png" width="240" alt="Welcome: guest or personal setup"/>
  <img src="assets/screenshots/guide/guest-choice.png" width="240" alt="Choose the Free or Pro guest demo"/>
</p>

1. Tap **Continue as a guest**.
2. Choose **Continue without Pro** or **Continue with Pro**.
3. Every main page shows **Demo · fictional data · 2 PM**. Use **Free / Pro** to compare features.
4. Try calendar changes, goal planning and weight entry: the demo uses in-memory fictional data.
5. Tap **Use my account** to leave. From personal mode, return through **You → Try the demo**.

Demo health, calendar and goals are separate from your real records. Voice preferences and
Gemini consent are app settings; the demo is not a separate cloud login. Enabling Gemini
allows demo questions and fictional tool results to be sent to Google.

### Free demo

Start with check-ins, your calendar, activity and goal tracking. Forecast and scheduling
buttons ask you to upgrade. Dash's proactive card offers **Tell me more / Not now**.

<p align="center">
  <img src="assets/screenshots/guide/demo-free-dash.png" width="240" alt="Free demo: Dash"/>
  <img src="assets/screenshots/guide/demo-free-predictions.png" width="240" alt="Free demo: forecast gate"/>
  <img src="assets/screenshots/guide/demo-free-plan.png" width="240" alt="Free demo: calendar"/>
</p>

### Pro demo

Pro adds forecasts, suggestions, Rescue and goal scheduling to the same fictional day.
With Gemini set up and allowed, you can also talk to Dash. Trying Pro in the demo is free;
it does not activate a subscription for your personal profile.

<p align="center">
  <img src="assets/screenshots/guide/demo-pro-predictions.png" width="240" alt="Pro demo: energy forecast"/>
  <img src="assets/screenshots/guide/demo-pro-plan.png" width="240" alt="Pro demo: suggested plan"/>
  <img src="assets/screenshots/guide/demo-pro-tomorrow.png" width="240" alt="Pro demo: goals"/>
</p>

</details>

## Set up your own account

Choose **Continue as a user** or **Use my account**. Add your name, connect Apple Health
and Calendar, then choose your preferences under **You**. Your profile stays on your device;
there is no email/password sign-in.

<details>
<summary>See personal setup, permissions and personal Pro screenshots</summary>

“Your account” currently means a **local profile** on the device, not an email/password
account. There is no app-managed cloud login or profile-sync setup in this build.

1. Choose **Continue as a user**, or **Use my account** from the demo.
2. Enter your name and age, then tap **Continue**.
3. Select **Connect Apple Health** and allow the records you want to use.
4. Select **Connect Calendar** to read events and enable planning writes.
5. Continue. You may use **Continue anyway** and connect missing sources later under **You**.
6. Decide whether to allow Gemini. This is separate from Health and Calendar permissions.
7. Open **You → Make it yours**, choose your preferences, then **Save**.
8. Start with a check-in. The energy forecast needs today's sleep and at least
   seven usable nights from the last 14 days. Until then, the app shows **Still learning**.

The screenshots below show **personal-account mode with a clean sample profile**, not the
author's private health or calendar records. A connected physical phone is needed to capture
those records; the phone was unavailable during this documentation run.

<p align="center">
  <img src="assets/screenshots/guide/personal-about.png" width="240" alt="Personal setup: profile form"/>
  <img src="assets/screenshots/guide/personal-connect.png" width="240" alt="Personal setup: source connections"/>
  <img src="assets/screenshots/guide/personal-home.png" width="240" alt="Personal mode: clean profile"/>
</p>
<p align="center">
  <img src="assets/screenshots/guide/personal-settings.png" width="240" alt="Personal mode: settings"/>
  <img src="assets/screenshots/guide/personal-connections.png" width="240" alt="Personal mode: Health, Calendar and Gemini connections"/>
</p>

### Personal Pro: the same features outside the demo

The screenshots below are from **personal mode with a simulated Pro subscription**.
They use a clean sample profile, not private phone data. The purchase was simulated, and no
personal records were sent to Gemini for this test.

- **Plan tomorrow** is visible all day. The Tomorrow tab works in both modes.
- **Start conversation** is available on Dash. Pro users can start without waiting for an
  automatic check-in or an energy forecast. Gemini still needs a key, permission and internet.
- Add at least one goal to enable **Plan my day tomorrow**. The empty personal-profile
  screenshot shows the button disabled because there are no goals yet.
- Buying or restoring Pro updates access immediately. The guest toggle never unlocks
  your personal subscription.

<p align="center">
  <img src="assets/screenshots/guide/personal-pro-gemini-permission.png" width="240" alt="personal pro gemini permission"/>
  <img src="assets/screenshots/guide/personal-pro-start-conversation.png" width="240" alt="personal pro start conversation"/>
  <img src="assets/screenshots/guide/personal-pro-tomorrow.png" width="240" alt="personal pro tomorrow"/>
  <img src="assets/screenshots/guide/personal-pro-settings.png" width="240" alt="personal pro settings"/>
  <img src="assets/screenshots/guide/personal-planning-entry.png" width="240" alt="personal planning entry"/>
</p>

</details>

## Use every feature

| What you want to do | Where to go |
|---|---|
| Check in and talk to Dash | **Dash** — report how you feel; start a Pro voice or text conversation. |
| Find a good time to focus | **Predictions** — see Pro forecasts, explanations and your week recap. |
| See your health and activity | **Activity** — steps, sleep, workouts and other available Apple Health data. |
| Organize a busy day | **Plan** — browse your calendar; use Pro suggestions and Rescue my day. |
| Turn goals into a schedule | **Tomorrow** — track today's and tomorrow's goals; Pro schedules them. |
| Make the app yours | **You** — connections, reminders, preferences, voices and subscription. |

You can also see your next activity on the Lock Screen and Dynamic Island, and add a Home
Screen widget.

<details>
<summary>Open the complete step-by-step guide, with screenshots of every feature</summary>

The bottom bar has **six tabs**: Dash, Predictions, Activity, Plan, Tomorrow and You.
The chat button opens the conversation interface; it is not a seventh bottom tab.

### 1. Dash, check-ins and energy states

Open **Dash** for the day's estimate, greeting and next event. Drag Dash to rotate him;
tap him to start speaking on a supported device. **See all of Dash** opens the character
showcase with states and gestures. The app also has energy-state icon variants.

When **How do you feel right now?** appears, tap **Low**, **Okay** or **Good**. The card steps
aside and your answer adjusts suggestions without changing measured sleep. Check-ins recur
by time of day. They are useful even while the model is still learning.

### 2. Predictions and the week's story

Open **Predictions**. Pro sees peak focus, the likely dip and the hourly curve. Scroll for
the week's story and **You often ask**. The week recap describes better/harder days and
patterns using available records; it cannot establish a medical cause.

Choose **Why this plan?** to see measured inputs, estimates, missing history and the option
to report how you actually feel. A shared hourly curve is an illustration, not a sensor reading.

<p align="center">
  <img src="assets/screenshots/guide/demo-pro-predictions.png" width="240" alt="Hourly forecast"/>
  <img src="assets/screenshots/guide/demo-pro-predictions-more.png" width="240" alt="Further prediction and recap content"/>
  <img src="assets/screenshots/guide/why-this-plan.png" width="240" alt="Measured versus estimated explanation"/>
</p>

### 3. Activity, health coverage and weight

Open **Activity** for steps, active energy, sleep and weight. Scroll for Heart & Body,
movement, workouts and nutrition **when the source data exists**. Available tiles include
heart rate, resting HR, HRV, VO₂ max, respiratory rate, mindful minutes, flights, distance,
stand hours, workout duration/calories/distance, and dietary energy/protein/carbs/fat.
Missing metrics are omitted rather than shown as invented readings.

Tap the weight card to **Log weight** in pounds. In personal mode, saving requires Health
write permission; in the demo it stays in the fictional session. Set optional targets in
**Make it yours**. Weight does not affect the energy forecast.

**You → What myTwin can read** shows source coverage. Wearables and nutrition apps feed
myTwin through Apple Health; there is no separate Garmin or MyFitnessPal login in myTwin.

<p align="center">
  <img src="assets/screenshots/guide/demo-pro-activity.png" width="240" alt="Activity summary"/>
  <img src="assets/screenshots/guide/demo-pro-activity-more.png" width="240" alt="Activity details"/>
</p>

### 4. Step pace and optional automatic walks

Set a **Step goal** in **You → Make it yours**. **Activity** estimates the end-of-day total
from steps so far and your usual remaining activity. Enable **Add walks when I'm behind**
to allow short walks to be added to a free calendar gap.

This opt-in feature can write a walk automatically; it does **not** use the chat Confirm
button. Checks are spaced about two hours apart, limited to three walks per day, with at
most one pending walk and no night-time scheduling. Health sync and iOS background timing
can delay checks. Disable the toggle to stop automatic walk additions.

### 5. Day, week and individual calendar days

Open **Plan → Day** for timed rows and all-day events. Free sees existing events; Pro adds
suggestions in free gaps when a forecast is available. **Week** shows the next seven days;
tap a day to expand it, then tap **Week** to go back. Other days show their calendar events,
not today's energy suggestions.

Suggestions may include movement, a nap, caffeine timing and wind-down. Dismiss unwanted
suggestions; repeated dismissals influence future suggestions.

<p align="center">
  <img src="assets/screenshots/guide/calendar-week.png" width="240" alt="Seven-day calendar"/>
  <img src="assets/screenshots/guide/week-day-in-full.png" width="240" alt="A selected day expanded"/>
</p>

### 6. Rescue my day — Pro

1. Open **Rescue my day** from Dash or Plan.
2. Select an existing flexible activity or **Add a new flexible activity**.
3. Pick the activity and duration. Optionally enable **Choose the time**.
4. Tap **Preview my rescue**. Read the proposed before/after and explanation.
5. Tap **Confirm demo change** in the demo, or **Confirm calendar change** in personal mode.
6. Use **Undo change** on the dashboard if you want to reverse the rescue.

Rescue preserves fixed appointments and only changes the app-managed activities in the
preview. It changes your plan, not your measured energy. An occupied requested time may
be shifted to the next free slot, which is explained in the preview.

<p align="center">
  <img src="assets/screenshots/guide/rescue-preview.png" width="240" alt="Rescue preview before confirmation"/>
  <img src="assets/screenshots/guide/confirmed-sample-rescue.png" width="240" alt="Confirmed demo rescue with undo"/>
</p>

### 7. Feedback and Up next

After an app-suggested activity ends, answer **Better**, **Same**, **Worse** or **I skipped it**.
Repeated feedback can change which activities are suggested; small samples are labelled.
After answering, **Up next** shows the next event and a short contextual tip. Feedback stays
local. It does not prove that an activity changed your health.

### 8. Today's goals, editing, completion and streaks

Open **Tomorrow**: the top of this page also manages **today**.

1. Use **Add a goal for today** or **Say today's goals**.
2. Include a duration/time if useful: `Finish report, 2 hrs` or `Call mom at 7pm`.
3. Tap a goal's name to edit its title, duration, category or time; use **Save**. The editor
   also offers **Delete goal**.
4. Tap the check circle to mark it done. Completed days build a streak; Dash celebrates
   finishing the last goal.
5. Use **Move … unfinished to tomorrow** to carry unfinished work forward.
6. With Pro, tap **Plan the rest of today** to schedule remaining goals around today's events.

<p align="center">
  <img src="assets/screenshots/guide/editing-a-goal.png" width="240" alt="Goal editor"/>
  <img src="assets/screenshots/guide/today-planned.png" width="240" alt="Today goals scheduled"/>
  <img src="assets/screenshots/guide/dash-celebrates.png" width="240" alt="Completed goals and streak celebration"/>
</p>

### 9. Tomorrow's goals and changing planned times — Pro scheduling

1. In **Tomorrow**, scroll to **Goals for …** and write one goal per line.
2. Add lengths or times naturally: `Finish lit review, 2 hrs, morning`, `Call mom at 7pm`,
   `Gym 45 min`. Or tap **Say your goals**, speak, and finish the recording.
3. Review the text. On-device goal splitting only retains words you actually said.
4. Tap **Done** to close the keyboard.
5. Pro: tap **Plan my day tomorrow**. This action writes the planned goals to the calendar;
   it is not a chat proposal awaiting a second Confirm button.
6. Tap a planned time, adjust it, then **Save**. Planning again preserves chosen times and
   reports whether anything new was scheduled. Overlaps are flagged.

Free can write, edit, complete and carry goals; scheduling opens the Pro paywall. Planned
goals receive event reminders, and permitted notifications provide a morning list and an
evening completion reminder. **Plan tomorrow** is available on Dash all day, in both personal and demo modes.

<p align="center">
  <img src="assets/screenshots/guide/tomorrow-planned.png" width="240" alt="Tomorrow goals scheduled"/>
  <img src="assets/screenshots/guide/changing-the-time.png" width="240" alt="Change a planned time"/>
  <img src="assets/screenshots/guide/time-changed.png" width="240" alt="Updated goal time"/>
</p>

### 10. Tomorrow's sleep what-if — Pro

Scroll to tomorrow's outlook. Change expected sleep with the stepper and compare the result.
It uses the shipped model with assumed typical sleep quality/stages and resting heart rate.
It needs seven recent usable nights; otherwise it says **Still learning**. It shows a possible outcome, not a promise about how you will feel. It does not change
your Apple Health records.

<p align="center">
  <img src="assets/screenshots/guide/tomorrow-prediction.png" width="240" alt="Tomorrow outlook"/>
  <img src="assets/screenshots/guide/tomorrow-after-a-short-night.png" width="240" alt="Outlook after reducing expected sleep"/>
</p>

### 11. Start a conversation, or let Dash speak first

Dash may speak up about a low-energy meeting, a coming dip, an upcoming suggestion, a step
walk, prolonged sitting or a week recap. He spaces nudges and respects quiet hours.

**Free:** read the one-line card and choose **Tell me more** or **Not now**.

**Pro with Gemini enabled:**

1. Tap **Start conversation** on Dash, or answer an automatic check-in. It uses today's calendar, goals and available forecast. You do not need a completed health baseline to start manually.
2. When Dash finishes speaking, the mic opens after a short pause.
3. Answer aloud; about **three seconds of silence** sends the reply. Tap **Send voice message**
   (or Dash) to send sooner. The recognised words appear on the card.
4. Or tap **Type your answer** and Send. Typing stops dictation so both inputs cannot send together.
5. Dash remembers the conversation, coaches briefly and asks a follow-up question.
6. Tap **End**, say “thanks, that's all,” or remain silent for about **30 seconds** to finish.
   Typing mode has no silence countdown.

If your personal account appears locked, check **You → myTwin Pro** or restore purchases from the paywall. The demo switch does not grant a personal subscription. Your Pro access updates when the purchase or restore completes.

The mentor uses **Gemini-generated voice**, with no local-voice fallback. It requires Pro,
your permission, internet access and a Gemini key. A microphone problem still allows typed replies.
Switching apps, leaving the screen or turning off access ends the conversation.

<p align="center">
  <img src="assets/screenshots/guide/mentor.png" width="240" alt="Gemini mentor after a typed reply"/>
</p>

### 12. Regular chat, calendar proposals and repeated questions

Tap the chat button and type, or use the voice control. Outside the mentor, say **“twin”**
for hands-free input or tap Dash to start/finish dictation. Regular hands-free sending uses
a longer pause than the mentor. Speech recognition runs on-device.

Try: “What do I have tomorrow?”, “Which goals are left?”, or “How did my week go?” Regular
chat uses Apple Foundation Models when available; Pro can use Gemini with consent and
internet. Dash can use your calendar, health summary, daily plan, week recap, goals and streaks
to answer your questions.

To add, move or remove **today's** calendar events, ask Dash, review the proposal and tap
**Confirm**. **Cancel** discards it. A generated reply alone does not save an event.

**You often ask** collects repeated questions over the last two weeks and provides starters
for new users. Pro shows saved answers and can ask again; Free shows the upgrade gate.
Demo questions do not enter your personal question history.

### 13. Preferences, voices and quiet hours

Open **You → Make it yours**:

| Setting | What to do |
|---|---|
| Preferred activity / usual time / equipment | Choose activities and durations that fit you. |
| Bedtime | Set your usual bedtime; planning uses it for coffee/wind-down timing. |
| Step / active-energy / weight targets | Enable only the optional targets you want and enter values. |
| Sleep goal | Adjust the hours; this also seeds tomorrow's expected sleep. |
| Add walks when I'm behind | Opt into automatic step-walk calendar additions. |
| Morning / event / wind-down reminders | Choose which reminder types you want. |
| Bedtime in my calendar | Add/update an app-managed bedtime event; switch off to remove it. |
| Quiet hours | Choose start/end; equal times disable quiet hours. |

Tap **Save**, or **Cancel** to discard preference edits. These are user-selected targets,
not medically prescribed goals. Calendar reminders and goals also require notification access.

Open **You → Dash's voice** to select an available iPhone voice or a Pro Gemini voice.
iPhone previews use system speech; Gemini's selected voice is used in Gemini sessions.
Enhanced device voices depend on voices downloaded in iOS.

<p align="center">
  <img src="assets/screenshots/guide/preferences-goals.png" width="240" alt="Preferences and optional targets"/>
  <img src="assets/screenshots/guide/preferences-reminders.png" width="240" alt="Reminders and quiet hours"/>
  <img src="assets/screenshots/guide/gemini-voices.png" width="240" alt="Voice selection"/>
</p>

### 14. Home Screen widget, Live Activity and background updates

Add the **myTwin widget** from the Home Screen's widget picker; small and medium sizes show
the day's estimate and advice, shared through the App Group.

**Up next** can appear on the **Lock Screen** and **Dynamic Island** for the next event or
goal. Open the app with an upcoming item and allow Live Activities in iOS. Pro can include
the forecast. The Live Activity updates when the app updates its next item; there is no
push server continuously advancing it while the app stays closed.

HealthKit background delivery can refresh the estimate and step check when sources sync.
Notifications include morning check-ins, event reminders, wind-down, step walks and goal
reminders. iOS controls delivery and background execution; neither is an exact-time guarantee.

<p align="center">
  <img src="assets/screenshots/guide/dynamic-island.png" width="240" alt="Up next in Dynamic Island"/>
  <img src="assets/screenshots/guide/lock-screen.png" width="240" alt="Up next on the Lock Screen"/>
</p>

</details>

## Free versus Pro

| Feature | Free | Pro |
|---|:---:|:---:|
| Dash, daily estimate, check-ins, week recap, explanations | ✓ | ✓ |
| Activity metrics, optional targets, weight logging | ✓ | ✓ |
| Day/week calendar, widget, reminders, Up next | ✓ | ✓ |
| Step pace and opt-in automatic walks; bedtime event | ✓ | ✓ |
| Write/edit/complete/carry goals; streaks and celebrations | ✓ | ✓ |
| On-device chat, when Apple Intelligence is available | ✓ | ✓ |
| Hourly forecast and tomorrow sleep what-if | Locked | ✓ |
| Suggestions based on estimated energy and Rescue my day | Locked | ✓ |
| Plan remaining goals today / plan tomorrow | Locked | ✓ |
| Answers and shortcuts on You often ask | Locked | ✓ |
| Gemini answers and Gemini voice | Locked | With permission, key and internet |
| Dash conversations with voice and typed replies | One-line card | With Gemini |

In personal mode, choose **You → Get myTwin Pro** or tap a locked feature. Select an available
plan on the paywall. An existing subscriber can use **myTwin Pro → Manage or restore your plan**
and the restore controls. Prices and available packages come from RevenueCat; read the
current paywall rather than relying on a hard-coded price in this README.

The shipped configuration uses **RevenueCat Test Store**: its purchases are simulated.
The Debug-only **Reset to free** control creates a fresh anonymous RevenueCat test user;
it is not cancellation of an App Store subscription. The demo's Free/Pro switch affects
only the demo.

<p align="center">
  <img src="assets/screenshots/guide/paywall-names-the-feature.png" width="240" alt="Paywall explains the locked feature"/>
</p>


<details>
<summary>More screenshots: both tiers, goals, settings and voice selection</summary>

<img src="assets/screenshots/guide/goal-added-for-today.png" width="240" alt="Goal added for today"/>
<img src="assets/screenshots/guide/voice-picker.png" width="240" alt="voice-picker"/>
<img src="assets/screenshots/guide/demo-pro-you.png" width="240" alt="demo-pro-you"/>
<img src="assets/screenshots/guide/demo-pro-tomorrow-more.png" width="240" alt="demo-pro-tomorrow-more"/>
<img src="assets/screenshots/guide/demo-pro-plan-more.png" width="240" alt="demo-pro-plan-more"/>
<img src="assets/screenshots/guide/demo-free-you.png" width="240" alt="demo-free-you"/>
<img src="assets/screenshots/guide/demo-free-tomorrow-more.png" width="240" alt="demo-free-tomorrow-more"/>
<img src="assets/screenshots/guide/demo-free-tomorrow.png" width="240" alt="demo-free-tomorrow"/>
<img src="assets/screenshots/guide/demo-free-plan-more.png" width="240" alt="demo-free-plan-more"/>
<img src="assets/screenshots/guide/demo-free-activity-more.png" width="240" alt="demo-free-activity-more"/>
<img src="assets/screenshots/guide/demo-free-activity.png" width="240" alt="demo-free-activity"/>
<img src="assets/screenshots/guide/demo-free-predictions-more.png" width="240" alt="demo-free-predictions-more"/>

</details>

## Configure integrations

The basic guest demo is ready to run. To talk to Dash, add a Gemini key using the steps
below. For your own calendar and health records, allow access during personal setup.

<details>
<summary>Open setup instructions for Gemini, Apple Health, Calendar and RevenueCat</summary>

### Apple Health and Calendar

Use the onboarding Connect buttons or **You**. Review app permissions in iOS Settings/Health
if access was denied. Your watch or third-party app must first write records into Apple
Health. Not every source provides every metric, and device syncing can be delayed.

Calendar read/write access is needed for actual scheduling. A user without connected data
can still check in, manage goal text and explore the guest demo. Do not mistake the fictional
demo's filled charts for evidence that personal data has connected.

### Gemini: required for the Pro mentor

1. Obtain a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).
2. From the repository root:

   ```sh
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

3. Replace `your-key-here` in `Secrets.xcconfig` with your key, without quotes. Do not paste
   the key into Swift, the README or screenshots. This file is git-ignored.
4. Rebuild: `Base.xcconfig` includes the optional secret and the app reads `GeminiAPIKey`
   from its built Info.plist. Runtime editing of the source file does not update an installed app.
5. Use Pro or the Pro demo, stay online, and allow Gemini when asked. Personal mode also has
   **You → Change Gemini permission**.
6. Choose a Gemini voice under **Dash's voice**, then test typed input first.

The client uses `gemini-3.8-live` over the Gemini Live WebSocket API. Spoken input is
transcribed locally; Gemini streams audio and its text transcription. A conversation waits
for the server's completed turn and local playback before automatic listening resumes.
Model availability, quota and billing depend on your Google project. See Google's
[Live API guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities).

Without a working key/consent/internet, the visual demo still works and regular chat can
use Apple's model where available. **The Pro mentor has no local-model/voice fallback.**
The development key is embedded in the installed client; a public production release needs
a considered credential strategy rather than treating a bundled secret as protected.

### RevenueCat: existing demo or your own project

For the hackathon demo, keep the existing public SDK key in `Config/Base.xcconfig`. To use
your own RevenueCat project:

1. Create the app/Test Store in RevenueCat.
2. Create products and attach them to entitlement **`mytwin_pro`** (the exact identifier the app checks).
3. Add products/packages to an offering and mark the offering current.
4. Configure/publish a paywall if using the dashboard-designed paywall; the app has a SwiftUI fallback.
5. Set `REVENUECAT_API_KEY` to your app's **public SDK key**, rebuild and test purchase/restore.
6. Before distribution, configure the real App Store products and credentials, production
   SDK key, entitlements, working privacy/terms links and signing. Validate the complete flow.

Reference: [RevenueCat SDK configuration](https://www.revenuecat.com/docs/getting-started/configuring-sdk)
and [products, entitlements and offerings](https://www.revenuecat.com/docs/projects/configuring-products).
Never embed a RevenueCat secret REST API key in the app.

### Widget and device configuration

Both app and extension must use the same App Group, matching `Shared/TwinState.swift`.
Verify the app's HealthKit entitlement, microphone/speech/calendar/Health usage descriptions,
Live Activity support and the extension's bundle/signing settings. No custom backend or
push-notification server is implemented for the Live Activity.

</details>

## Privacy and calendar writes

| Feature | What happens |
|---|---|
| Local model / speech | Supported Apple on-device services process answers/transcription. |
| Gemini allowed + Pro online | With your permission, Google can receive your questions and the calendar, goals, health summary, forecast or week recap needed to answer them. |
| Guest demo | Fictional health/calendar/goals; no real Health/calendar writes from demo actions. |
| Local profile/preferences/goals/history | Stored locally; not an app-managed cloud account. |
| RevenueCat | Handles subscription state with the SDK's app user identity. |
| Chat/mentor calendar proposal | Saved only by **Confirm**; Cancel discards. |
| Rescue | Preview, then explicit confirmation; undo is available. |
| Goal planning/time edits | Pressing the planning button or Save writes the selected changes. |
| Automatic walks / bedtime | Optional settings authorize app-managed calendar writes. |

Turn Gemini off in **You** to stop future Gemini use. Revoking consent ends the active
mentor. The app is a planning/wellness prototype, not a medical device.

## Troubleshooting

| What you see | Check next |
|---|---|
| Still learning / no forecast | Today's sleep and seven usable recent nights; Health access and source syncing. Use check-ins/demo meanwhile. |
| Empty activity tiles or fewer metrics | Does Apple Health contain that metric? Missing values are hidden; a connected source may not export it. |
| Mentor doesn't start | Tap Start conversation on Dash. Check Pro, Gemini key, Allow and internet. Automatic check-ins also depend on quiet hours/nudge spacing; manual conversations do not require a forecast. |
| Gemini unavailable | Key/model access, internet, quota and Google project configuration. Rebuild after changing the key. |
| No microphone / on-device dictation unavailable | Test a real supported iPhone, permit microphone/speech, check language/model readiness; type instead. |
| Apple chat unavailable | Apple Intelligence device/model availability; use configured Pro Gemini or the visual demo. |
| Nothing changed on the calendar | Confirm a chat proposal or rescue; grant Calendar access. Demo changes stay in the demo. |
| No purchase packages | Network, current RevenueCat offering, products and exact entitlement `mytwin_pro`. |
| No reminders / Live Activity | iOS permission settings, quiet hours and upcoming items. Reopen to refresh; background timing is system-controlled. |
| Widget stale or empty | Matching App Group/signing, current personal prediction and iOS widget refresh timing. |
| Stuck in the guest demo | Tap Use my account and remove `--sample-day` / `--demo-free` launch arguments. |
| Goal speech splits poorly | Review/edit text before planning; spoken goal splitting needs supported on-device services. |

## Testing and screenshots

We checked the main flows with **90 unit tests and 15 app walkthroughs**, including
personal Pro access and a Gemini conversation. The **54 screenshots** are real app captures
from Simulator. Personal-mode images use a clean sample profile, not private phone records.

Voice input, echo handling, Bluetooth and live Health syncing still need testing on a phone.

<details>
<summary>For developers: test commands and screenshot details</summary>

```sh
# Pick an installed simulator first.
xcrun simctl list devices available
xcodebuild test -project myTwin.xcodeproj -scheme myTwin   -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE'   -only-testing:myTwinTests

# Opt-in live Gemini test: uses fictional demo data and your configured API key.
TEST_RUNNER_MYTWIN_LIVE_TESTS=1 xcodebuild test   -project myTwin.xcodeproj -scheme myTwin   -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE'   -only-testing:myTwinUITests/MentorLiveUITests

# Opt-in README screenshots: saved as retained XCTest attachments.
TEST_RUNNER_MYTWIN_README_SHOTS=1 xcodebuild test   -project myTwin.xcodeproj -scheme myTwin   -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE'   -only-testing:myTwinUITests/ReadmeScreenshotTests   -only-testing:myTwinUITests/ReadmeDetailScreenshotTests   -only-testing:myTwinUITests/ReadmeForecastScreenshotTests   -only-testing:myTwinUITests/ReadmeLiveActivityScreenshotTests
```

The documentation capture also passed nine main walkthroughs, five detail/live walkthroughs,
and a personal Pro Test Store integration check. After the personal-mode fixes, all 90 unit
tests passed again. To repeat the personal Pro check against the configured Test Store:

```sh
TEST_RUNNER_MYTWIN_TEST_STORE=1 xcodebuild test \
  -project myTwin.xcodeproj -scheme myTwin \
  -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE' \
  -only-testing:myTwinUITests/PersonalProUITests
```

This test accepts only RevenueCat's explicitly labelled simulated purchase sheet.

See the [screenshot notes](assets/screenshots/guide/README.md) for capture details and the
[verification notes](docs/verification.md) for device checks. Earlier mentor testing also
included two UI checks, five multi-turn Gemini conversations with fictional data and five
calendar-proposal checks.

</details>

## Meet Dash

Dash is a completely original 3D character, modelled, rigged and animated in **Blender** and
running live in **RealityKit**. He isn't a static mascot. His posture, breathing, face and
glow come from your real energy estimate, so you can read your day from across the room.

- 🎨 Hand-built in Blender: sculpted hair, a cloth jacket, and a baked normal map for skin, hair and fabric
- 😀 **16 face blend shapes**: eyes, brows and mouth all move
- 🎬 **9 animation clips** on one timeline, exported as a single USDZ
- 🔆 Real-time lighting: his room and platform glow in the colour of your battery
- 👆 Drag to spin him; tap him to talk

<details>
<summary>See Dash’s energy states, animations and character art</summary>

### Four energy states

Rendered in Blender:

<p align="center"><img src="assets/Dash/renders/Dash_States.png" width="820" alt="Dash in four energy states, rendered in Blender"/></p>

The same four states, live in the app, each with its own glow:

<p align="center"><img src="assets/screenshots/dash_states_app.jpg" width="820" alt="Dash's four states in the app: energetic, normal, tired, exhausted"/></p>

| State | Charge | What you see |
|---|---|---|
| 🟢 **Energetic** | 80–100% | Stands tall, bouncy breathing, bright eyes. Breaks into a wave or a jump on his own. |
| 🔵 **Normal** | 55–79% | Relaxed and easy. Stretches now and then. |
| 🟠 **Tired** | 30–54% | Shoulders drop, breathing slows, and the yawns start. |
| 🔴 **Exhausted** | 0–29% | Barely upright, eyes heavy. Dozes off mid-idle. |

### Dash in motion

Recorded live in the app. On top of each idle loop, Dash plays gestures that suit his
mood: he waves and jumps when he's energetic, yawns when he's tired, and nods off when he's
exhausted. He also waves to get your attention when he has something to tell you.

<table>
<tr>
<td align="center"><img src="assets/Dash/videos/dash_wave.gif" width="200" alt="Dash waving"/><br/><b>👋 Greeting</b><br/><sub>Energetic · says hello when he speaks up</sub></td>
<td align="center"><img src="assets/Dash/videos/dash_jump.gif" width="200" alt="Dash jumping"/><br/><b>⚡ Jump</b><br/><sub>Energetic · rested and charged</sub></td>
<td align="center"><img src="assets/Dash/videos/dash_yawn.gif" width="200" alt="Dash yawning"/><br/><b>🥱 Yawn</b><br/><sub>Tired · running low</sub></td>
<td align="center"><img src="assets/Dash/videos/dash_doze.gif" width="200" alt="Dash dozing off"/><br/><b>😴 Doze</b><br/><sub>Exhausted · nodding off</sub></td>
</tr>
</table>

### Character sheets

<table>
<tr>
<td align="center"><img src="assets/Dash/renders/Dash_Hero.png" width="220"/><br/><sub>Hero pose</sub></td>
<td align="center"><img src="assets/Dash/renders/Dash_ThreeQuarter.png" width="220"/><br/><sub>Three-quarter</sub></td>
<td align="center"><img src="assets/Dash/renders/Dash_Side.png" width="220"/><br/><sub>Side</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/Dash/renders/Dash_Front.png" width="220"/><br/><sub>Front</sub></td>
<td align="center"><img src="assets/Dash/renders/Dash_Back.png" width="220"/><br/><sub>Back: jacket detail</sub></td>
<td align="center"><img src="assets/Dash/renders/Dash_Face.png" width="220"/><br/><sub>Face: 16 blend shapes</sub></td>
</tr>
</table>

---

</details>

## Honest limits

The model found small improvements in tracking day-to-day changes, but it did not improve
the accuracy of exact scores. Treat the percentage and hourly curve as a guide, not a precise
measurement. The [model write-up](ml/README.md) explains the results and limitations.

<details>
<summary>Read the model evaluation results</summary>

The model predicts **direction, not a number**. Measured with leave-one-person-out
evaluation on [PMData](https://datasets.simula.no/pmdata/) (16 people, 1,747 labelled days):

| Target | Mean within-person correlation | People improved | Wilcoxon p |
|---|---|---|---|
| Fatigue | -0.054 → +0.103 | 12/16 | 0.0034 |
| Readiness | +0.051 → +0.124 | 14/16 | 0.0021 |

Readiness MAE is 1.152 for the baseline and 1.155 for the model: absolute accuracy does not
improve. That's why the app shows the percentage and hourly curve as **illustrations**, not
measurements of a body battery, and says so on screen.

A second dataset, LifeSnaps (71 people), gave no usable signal: within a person, tiredness
tracked the hour of the day and nothing else. That negative result, and why a five-weight
ridge regression beat LightGBM, is written up in [`ml/README.md`](ml/README.md).

</details>

## Project layout

Built with SwiftUI, RealityKit, Apple Health, Apple on-device models, Gemini and RevenueCat.

<details>
<summary>For developers: where the code lives</summary>

| Path | Purpose |
|---|---|
| `myTwin/ContentView.swift` | Six tabs, demo/Pro gates and integration of planning/voice |
| `myTwin/MentorConversation.swift` | Mentor turn lifecycle, speech/text answers and ending |
| `myTwin/ChatManager.swift`, `VoiceManager.swift` | Model tools, chat and local speech recognition/playback |
| `myTwin/Gemini/` | Consent, Live WebSocket protocol, Gemini audio/tools |
| `myTwin/Wellness/` | Check-ins, Rescue, goals, feedback, steps, tomorrow outlook and Live Activity |
| `myTwin/Dashboard/` | Activity, calendar, prediction and conversation cards |
| `myTwin/Avatar/` | RealityKit character, animation, lighting and showcase |
| `myTwin/Pro/` | RevenueCat entitlement, purchase/restore and paywall |
| `myTwinWidget/`, `Shared/` | Widget/Live Activity views, shared model/state |
| `Config/` | Build configuration; ignored private Gemini key |
| `myTwinTests/`, `myTwinUITests/` | Unit, UI, live-network and opt-in capture suites |
| `assets/` | App screenshots, Blender sources, renders and animations |
| `ml/` | Training, evaluation, limitations and negative results |

Training datasets are not bundled; consult `ml/README.md` and the source dataset licences
before downloading or reusing them.

</details>

## Licence

MIT. See [LICENSE](LICENSE).
