import Foundation

/// The last seven days told as a few sentences instead of a chart: the best day and what
/// came before it, the hardest day and why, and one pattern across the week.
///
/// Every claim compares a night with this person's own usual, worked out from the same
/// history the energy model reads. If the data doesn't show a reason, it says so rather
/// than inventing one.
enum WeekRecap {
    /// With fewer days than this, "best" and "hardest" mean very little.
    static let minimumDays = 4

    /// `history` is newest first, as HealthManager returns it. Empty when there isn't
    /// enough to say anything honest.
    static func lines(history: [DaySignals], model: EnergyModel, now: Date = .now) -> [String] {
        // Replay the model for each of the last seven days, using only what was known then.
        let days: [(night: DaySignals, score: Double)] = (0..<7).compactMap { offset in
            let slice = Array(history.dropFirst(offset))
            guard let night = slice.first, let reading = model.reading(from: slice) else { return nil }
            return (night, reading.deviation)
        }
        guard days.count >= minimumDays,
              let best = days.max(by: { $0.score < $1.score }),
              let hardest = days.min(by: { $0.score < $1.score }),
              best.score > hardest.score
        else { return [] }

        let usual = Usual(history)
        var lines = [
            "Your best day was \(name(best.night.date, now: now)). "
                + reason(best.night, usual, good: true, before: night(best.night.date, now: now)),
            "The hardest was \(name(hardest.night.date, now: now)). "
                + reason(hardest.night, usual, good: false, before: night(hardest.night.date, now: now)),
        ]
        if let pattern = pattern(days.map(\.night)) { lines.append(pattern) }
        return lines
    }

    /// The same recap as one block of text, for the chatbot to read.
    static func text(history: [DaySignals], model: EnergyModel?) -> String {
        guard let model else { return "No energy model is loaded." }
        let lines = lines(history: history, model: model)
        return lines.isEmpty
            ? "Not enough nights of sleep data yet to recap the week. It needs at least \(minimumDays)."
            : lines.joined(separator: " ")
    }

    // MARK: - Why a day went the way it did

    /// This person's averages across all the history there is, not just this week, so one
    /// odd week doesn't redefine "usual".
    private struct Usual {
        let sleep, restingHR, deep: Double?
        init(_ history: [DaySignals]) {
            func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            sleep = mean(history.compactMap(\.asleepMinutes))
            restingHR = mean(history.compactMap(\.restingHR))
            deep = mean(history.compactMap(\.deepMinutes))
        }
    }

    /// Up to two things about the night before that stood out in the direction of the day.
    /// Each is weighed by how far past its own threshold it went, so the biggest leads.
    private static func reason(_ night: DaySignals, _ usual: Usual, good: Bool, before: String) -> String {
        var facts: [(size: Double, clause: String)] = []

        if let slept = night.asleepMinutes, let normal = usual.sleep {
            let gap = slept - normal
            if good ? gap >= 30 : gap <= -30 {
                facts.append((abs(gap) / 30,
                              "you slept \(hours(slept)) \(before), \(duration(abs(gap))) \(good ? "more" : "less") than usual"))
            }
        }
        if let heart = night.restingHR, let normal = usual.restingHR {
            let gap = heart - normal
            if good ? gap <= -2 : gap >= 2 {
                facts.append((abs(gap) / 2,
                              "your resting heart rate was \(Int(abs(gap).rounded())) bpm \(good ? "below" : "above") your normal"))
            }
        }
        if let deep = night.deepMinutes, let normal = usual.deep {
            let gap = deep - normal
            if good ? gap >= 10 : gap <= -10 {
                facts.append((abs(gap) / 10,
                              "you got \(Int(abs(gap).rounded())) \(good ? "more" : "fewer") minutes of deep sleep than usual"))
            }
        }

        guard !facts.isEmpty else {
            return good ? "Nothing stood out \(before) — just a steady run."
                        : "Nothing in your sleep or heart rate explains it; some dips have no single cause."
        }
        let sentence = facts.sorted { $0.size > $1.size }.prefix(2).map(\.clause).joined(separator: ", and ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }

    /// One thing true across the whole week, if anything is.
    private static func pattern(_ nights: [DaySignals]) -> String? {
        let slept = nights.compactMap(\.asleepMinutes)
        let short = slept.filter { $0 < 7 * 60 }.count
        if short >= 3 { return "\(short) of the last \(slept.count) nights were under 7 hours." }

        // Bedtimes either side of midnight: 23:30 and 00:30 are an hour apart, not 23.
        let bedtimes = nights.compactMap(\.bedHour).map { $0 < 12 ? $0 + 24 : $0 }
        if let early = bedtimes.min(), let late = bedtimes.max(), late - early >= 1.5 {
            return "Your bedtime moved around by about \(hours((late - early) * 60)) across the week."
        }
        if slept.count >= minimumDays, short == 0 { return "Every night this week was 7 hours or more." }
        return nil
    }

    // MARK: - Words

    private static func name(_ date: Date, now: Date) -> String {
        let days = Calendar.current
        if days.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = days.date(byAdding: .day, value: -1, to: now), days.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "last night" for today, "the night before" for any other day.
    private static func night(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? "last night" : "the night before"
    }

    private static func hours(_ minutes: Double) -> String {
        String(format: "%.1f hours", minutes / 60)
    }

    /// Rounded to five minutes, since the watch isn't more precise than that.
    private static func duration(_ minutes: Double) -> String {
        let rounded = Int((minutes / 5).rounded()) * 5
        let (h, m) = (rounded / 60, rounded % 60)
        switch (h, m) {
        case (0, _): return "\(m) minutes"
        case (_, 0): return h == 1 ? "1 hour" : "\(h) hours"
        default: return "\(h) hour\(h == 1 ? "" : "s") \(m) minutes"
        }
    }
}
