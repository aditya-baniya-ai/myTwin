import Foundation

/// One short line on how to do well in the next thing on your calendar, from what kind of
/// event it is and how much energy you'll likely have for it.
enum EventTips {
    enum Kind { case meeting, learning, training, social, bedtime, other }
    enum Energy { case high, middle, low }

    /// `charge` is the forecast at the event's start (Pro); without it, how you said you
    /// feel stands in. With neither, the tip is about the event alone.
    static func tip(title: String, isActivity: Bool = false, charge: Double?,
                    reported: ReportedEnergy?) -> String {
        let level = energy(charge: charge, reported: reported)
        let advice = line(kind(of: title, isActivity: isActivity), level)
        guard let charge else { return advice }
        return "You'll be at about \(Int(charge * 100))% then. " + advice   // as the app shows it
    }

    static func kind(of title: String, isActivity: Bool = false) -> Kind {
        if isActivity { return .training }
        if title.lowercased().contains("bedtime") { return .bedtime }
        let words = title.lowercased()
        func has(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        if has(["gym", "run", "yoga", "workout", "strength", "lift", "soccer", "swim", "cycl",
                "training", "walk", "stretch", "pilates", "hike", "match", "game"]) { return .training }
        if has(["meeting", "standup", "stand-up", "sync", "call", "1:1", "interview", "demo",
                "review", "client", "presentation", "pitch"]) { return .meeting }
        if has(["class", "lecture", "study", "exam", "lab", "seminar", "course", "tutorial"]) { return .learning }
        if has(["lunch", "dinner", "breakfast", "coffee with", "birthday", "party", "drinks",
                "date", "market"]) { return .social }
        return .other
    }

    static func energy(charge: Double?, reported: ReportedEnergy?) -> Energy? {
        if let charge { return charge >= 0.65 ? .high : charge >= 0.45 ? .middle : .low }
        switch reported {
        case .good: return .high
        case .okay: return .middle
        case .low: return .low
        case nil: return nil
        }
    }

    private static func line(_ kind: Kind, _ energy: Energy?) -> String {
        switch (kind, energy) {
        case (.meeting, .high): "You're near your best: lead with the hardest decision while you're sharp."
        case (.meeting, .middle): "Write down the one point you need to make, and make it early."
        case (.meeting, .low): "Drink some water, stand for the first few minutes, and note action items so you don't have to remember them."
        case (.meeting, nil): "Know the one thing you need from it, and say it early."

        case (.learning, .high): "A good time to learn: sit near the front and tackle the hardest part."
        case (.learning, .middle): "Skim your notes for five minutes beforehand so the new parts stick."
        case (.learning, .low): "Have a snack before, and take notes by hand to stay switched on."
        case (.learning, nil): "Skim your notes for five minutes beforehand."

        case (.training, .high): "You're charged: a good day to push the main set."
        case (.training, .middle): "Warm up properly and keep the main set steady."
        case (.training, .low): "Keep it easy, or swap to mobility work. It still counts."
        case (.training, nil): "Warm up for five minutes first and keep water nearby."

        case (.social, .high): "Enjoy it; you'll have the energy to be fully there."
        case (.social, .middle): "Eat something beforehand so you're not running on empty."
        case (.social, .low): "Keep it short if you need to. Leaving early is fine on a low day."
        case (.social, nil): "Put your phone away and be fully there."

        case (.bedtime, _): "Screens down and lights low half an hour before, so you fall asleep on time."

        case (.other, .high): "You're near your best: do the part that needs the most focus first."
        case (.other, .low): "Have water and a short walk beforehand, and keep it simple."
        case (.other, _): "Take five minutes to prepare, and start with what matters most."
        }
    }
}
