import Foundation

/// One thing you want to get done on a day, read from a line you wrote.
struct Goal: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case personal, professional }
    enum Window: String, Codable {
        case morning, afternoon, evening
        var hours: Range<Int> {
            switch self { case .morning: 6..<12; case .afternoon: 12..<17; case .evening: 17..<23 }
        }
    }

    var id = UUID()
    var title: String
    var minutes: Int
    var kind: Kind
    var window: Window?
    /// A time you named ("at 3pm"), as hour and minute.
    var hour: Int?
    var minute: Int?
    var done = false
    /// Carried over to the next day at the nightly check.
    var moved = false
    /// Where Plan my day put it.
    var scheduled: Date?
}

/// Reads goals out of what you typed: one per line, with an optional length ("2 hrs",
/// "30 min"), a time ("at 3pm") or a part of the day ("morning"). No model needed, and the
/// same on every iPhone.
enum GoalParser {
    private static let work = ["work", "meeting", "email", "report", "study", "research", "paper", "project",
                               "code", "review", "class", "exam", "assignment", "client", "interview",
                               "apply", "application", "grant", "presentation", "lab", "thesis", "write",
                               "finish", "submit", "prepare", "poster", "lecture"]

    static func parse(_ text: String) -> [Goal] {
        text.split(whereSeparator: \.isNewline).compactMap { line(String($0)) }
    }

    static func line(_ raw: String) -> Goal? {
        var text = normalize(raw).trimmingCharacters(in: .whitespaces)
        text = text.replacing(/^\s*(?:[-•*]+|\d+[.)])\s*/, with: "")     // bullets and numbering
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let lower = text.lowercased()

        var minutes: Int?
        if let match = lower.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b/), let value = Double(match.1) {
            minutes = Int(value * 60)
            text = strip(match.range, from: text, lower: lower)
        } else if let match = lower.firstMatch(of: /(\d+)\s*(?:m|min|mins|minute|minutes)\b/), let value = Int(match.1) {
            minutes = value
            text = strip(match.range, from: text, lower: lower)
        }

        // "at 7", "at 7:30pm", or "7pm" on its own.
        var hour: Int?, minute: Int?
        let now = text.lowercased()
        var time: (range: Range<String.Index>, hour: Substring, minute: Substring?, half: Substring?)?
        if let match = now.firstMatch(of: /\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/) {
            time = (match.range, match.1, match.2, match.3)
        } else if let match = now.firstMatch(of: /\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/) {
            time = (match.range, match.1, match.2, match.3)
        }
        if let time, var value = Int(time.hour), (1...23).contains(value) {
            if time.half == "pm", value < 12 { value += 12 }
            if time.half == "am", value == 12 { value = 0 }
            hour = value
            minute = time.minute.flatMap { Int($0) } ?? 0
            text = strip(time.range, from: text, lower: now)
        }

        let window: Goal.Window? = lower.contains("morning") ? .morning
            : lower.contains("afternoon") ? .afternoon
            : ["evening", "tonight", "before bed", "at night"].contains(where: lower.contains) ? .evening : nil
        text = text.replacing(/(?i)\b(in the |this |tomorrow )?(morning|afternoon|evening|tonight|before bed|at night)\b/, with: "")

        let kind: Goal.Kind = work.contains { lower.contains($0) } ? .professional : .personal
        let title = tidy(text)
        guard !title.isEmpty else { return nil }
        return Goal(title: title.prefix(1).uppercased() + title.dropFirst(),
                    minutes: min(max(minutes ?? (kind == .professional ? 60 : 30), 5), 8 * 60),
                    kind: kind, window: window, hour: hour, minute: minute)
    }

    // MARK: - Spoken words

    private static let numbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "twenty five": 25, "twenty-five": 25, "thirty": 30, "forty": 40, "forty five": 45,
        "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
    ]
    private static let spokenLength = try! Regex(
        "(?i)\\b(twenty[- ]five|forty[- ]five|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty|ninety)( and a half)? (hours?|hrs?|minutes?|mins?)\\b")

    /// Speech as dictation writes it, in the forms the rest of the parser reads: "7 p.m."
    /// to "7pm", "two hours" to "2 hours", "half an hour" to "30 min", "noon" to "12pm".
    static func normalize(_ text: String) -> String {
        var out = text.replacing(/(?i)\b([ap])\.\s?m\b\.?/) { "\($0.1.lowercased())m" }
        out = out.replacing(/(?i)\bnoon\b/, with: "12pm")
        out = out.replacing(/(?i)\ban hour and a half\b/, with: "1.5 hrs")
        out = out.replacing(/(?i)\bhalf an hour\b/, with: "30 min")
        out = out.replacing(/(?i)\b(?:an|a|one) hour\b/, with: "1 hr")
        out = out.replacing(spokenLength) { match in
            let word = match.output[1].substring.map { String($0).lowercased() } ?? ""
            let half = match.output[2].substring == nil ? 0 : 0.5
            let unit = match.output[3].substring.map(String.init) ?? ""
            let value = (numbers[word] ?? 0) + half
            return "\(value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)) \(unit)"
        }
        return out
    }

    /// A goal's name without the words around it that speech brings: "I need to", "then",
    /// "maybe" in front, "for", "about", "that'll take" left over at the end.
    static func tidy(_ text: String) -> String {
        var out = text.replacing(/\s{2,}/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = /(?i)^(?:um+|uh+|so|okay|ok|well|and|then|also|maybe|just|first|finally|next|tomorrow|(?:just )?one (?:more )?thing|i (?:need|want|have|would like|'d like|’d like|'ll need|’ll need) to|i(?:'ll|’ll| will| should| must| gotta)|gotta)\b[\s,.:]*/
        let tail = /(?i)[\s,;:.·\-]*\b(?:for|about|around|roughly|take|takes|that'll|that’ll|that will|it'll|it’ll|it will|that|will|by|at|in|the|to|and|then|maybe|or so)\s*$/
        let edges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        while let match = out.firstMatch(of: lead), !match.output.isEmpty { out.removeSubrange(match.range) }
        out = out.trimmingCharacters(in: edges)
        while let match = out.firstMatch(of: tail) {
            out.removeSubrange(match.range)
            out = out.trimmingCharacters(in: edges)
        }
        return out
    }

    /// The same text without the matched part: the range was found in a lowercased copy of
    /// equal length, so it points at the same characters.
    private static func strip(_ range: Range<String.Index>, from text: String, lower: String) -> String {
        guard text.count == lower.count else { return text }      // a letter changed length: leave it
        let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let end = lower.distance(from: lower.startIndex, to: range.upperBound)
        var out = text
        out.removeSubrange(out.index(out.startIndex, offsetBy: start)..<out.index(out.startIndex, offsetBy: end))
        return out
    }
}

/// Puts a day's goals into its free time: named times first, then work in your strongest
/// hours, then personal goals, later in the day where there's room.
enum GoalPlanner {
    static func plan(_ goals: [Goal], on day: Date, busy: [DateInterval], wake: Int, bedtime: Date,
                     dayStart: Double = DayCharge.unknownDay) -> [UUID: Date] {
        let calendar = Calendar.current
        let open = calendar.date(bySettingHour: max(wake, 6), minute: 0, second: 0, of: day) ?? day
        let close = bedtime.addingTimeInterval(-3600)
        var taken = busy
        var placed: [UUID: Date] = [:]
        func free(_ start: Date, _ minutes: Int) -> Bool {
            let end = start.addingTimeInterval(Double(minutes) * 60)
            return start >= open && end <= close && !taken.contains { $0.start < end && $0.end > start }
        }
        func take(_ goal: Goal, _ start: Date) {
            placed[goal.id] = start
            taken.append(DateInterval(start: start, duration: Double(goal.minutes) * 60))
        }
        let slots = stride(from: open, to: close, by: 15 * 60).map { $0 }

        let order = goals.filter { !$0.done }.sorted { a, b in
            let rank = { (g: Goal) in g.hour != nil ? 0 : g.kind == .professional ? 1 : 2 }
            return rank(a) != rank(b) ? rank(a) < rank(b) : a.minutes > b.minutes
        }
        for goal in order {
            if let hour = goal.hour,
               let start = calendar.date(bySettingHour: hour, minute: goal.minute ?? 0, second: 0, of: day) {
                if free(start, goal.minutes) { take(goal, start) }
                continue
            }
            let fits = slots.filter { free($0, goal.minutes) }
            let inWindow = goal.window.map { window in fits.filter { window.hours.contains(calendar.component(.hour, from: $0)) } } ?? fits
            let choices = inWindow.isEmpty ? fits : inWindow
            func energy(_ date: Date) -> Double { DayCharge.remaining(from: dayStart, at: date) }
            let pick = goal.kind == .professional
                ? choices.first { energy($0) == choices.map(energy).max() }      // the earliest of your best hours
                : (choices.first { calendar.component(.hour, from: $0) >= 16 } ?? choices.last)
            if let pick { take(goal, pick) }
        }
        return placed
    }
}
