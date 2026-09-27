import Foundation

/// Preferences are explicit choices, not health prescriptions.
enum Movement: String, Codable, CaseIterable, Identifiable {
    case walk, pilates, strength, stretch, rest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: "Easy walk"
        case .pilates: "Gentle Pilates"
        case .strength: "Strength session"
        case .stretch: "Gentle stretch"
        case .rest: "Quiet recovery"
        }
    }
    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .pilates, .stretch: "figure.mind.and.body"
        case .strength: "dumbbell"
        case .rest: "leaf"
        }
    }
}

struct PlanningPreferences: Codable, Equatable {
    var movement: Movement = .walk
    var minutes = 20
    var hasEquipment = false
    var bedtimeHour = 23
    var bedtimeMinute = 0
    var stepGoal: Double? = nil
    var activeEnergyGoal: Double? = nil
    var weightGoal: Double? = nil
    var sleepGoal = 8.0
    var morningReminder = false
    var eventReminders = false
    var bedtimeReminder = false
    var quietStart = 21
    var quietEnd = 8

    var activityTitle: String {
        movement == .strength && !hasEquipment ? "Bodyweight strength" : movement.title
    }
    func bedtime(on now: Date = .now) -> Date {
        let calendar = Calendar.current
        let at = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: now) ?? now
        return bedtimeHour < 12 ? (calendar.date(byAdding: .day, value: 1, to: at) ?? at) : at
    }
    func isQuiet(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        if quietStart == quietEnd { return false }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
    }
    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "planning.preferences.v1"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "planning.preferences.v1") }
    }
}

enum ReportedEnergy: String, Codable, CaseIterable, Identifiable {
    case low, okay, good
    var id: String { rawValue }
    var title: String {
        switch self { case .low: "Low"; case .okay: "Okay"; case .good: "Good" }
    }
    var rating: Double {
        switch self { case .low: 1; case .okay: 3; case .good: 5 }
    }
}
struct EnergyCheckIn: Codable {
    let date: Date
    let energy: ReportedEnergy
}
enum ActionOutcome: String, Codable, CaseIterable, Identifiable {
    case better, same, worse
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
struct PlannedAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var eventID: String?
    var movement: Movement
    var title: String
    var start: Date
    var end: Date
    var beforeTitle: String?
    var reportedEnergy: ReportedEnergy?
    var completedAt: Date?
    var outcome: ActionOutcome?
    var skipped = false
    var isRescue = false
    var tracksOutcome: Bool? = nil
}

@MainActor @Observable
final class DailySupport {
    let isSample: Bool
    var preferences: PlanningPreferences
    private(set) var checkIn: EnergyCheckIn?
    private(set) var actions: [PlannedAction]
    var problem: String?
    private let defaults: UserDefaults

    init(isSample: Bool = false, defaults: UserDefaults = .standard) {
        self.isSample = isSample
        self.defaults = defaults
        preferences = isSample ? PlanningPreferences() : PlanningPreferences.load(defaults: defaults)
        if !isSample, let data = defaults.data(forKey: "daily.support.v1"),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            checkIn = saved.checkIn
            actions = saved.actions
        } else {
            actions = []
        }
        if isSample {
            let now = SampleDay.now
            checkIn = EnergyCheckIn(date: now, energy: .low)
            actions = [PlannedAction(eventID: "sample-workout", movement: .strength,
                                     title: "Strength session", start: SampleDay.at(17), end: SampleDay.at(18)),
                       PlannedAction(movement: .walk, title: "Easy walk", start: now.addingTimeInterval(-3600),
                                     end: now.addingTimeInterval(-2400))]
        }
    }
    /// The fictional demo never writes to a real calendar. Personal rescues require Pro.
    func canRescue(proEnabled: Bool) -> Bool { isSample || proEnabled }

    var currentCheckIn: ReportedEnergy? {
        guard let checkIn, Calendar.current.isDate(checkIn.date, inSameDayAs: isSample ? SampleDay.now : .now) else { return nil }
        return checkIn.energy
    }
    func report(_ energy: ReportedEnergy, now: Date = .now) {
        checkIn = EnergyCheckIn(date: isSample ? SampleDay.now : now, energy: energy)
        persist()
    }
    func savePreferences(_ value: PlanningPreferences) {
        preferences = value
        if !isSample { value.save(defaults: defaults) }
    }
    func save(_ action: PlannedAction, replacing old: PlannedAction? = nil) {
        if let old { actions.removeAll { $0.id == old.id } }
        actions.removeAll { $0.id == action.id }
        actions.append(action)
        persist()
    }
    func undo(_ action: PlannedAction, restoring old: PlannedAction?) {
        actions.removeAll { $0.id == action.id }
        if let old { actions.append(old) }
        persist()
    }
    func finish(_ action: PlannedAction, outcome: ActionOutcome?, skipped: Bool = false) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].completedAt = skipped ? nil : (isSample ? SampleDay.now : .now)
        actions[index].outcome = skipped ? nil : outcome
        actions[index].skipped = skipped
        persist()
    }
    /// These are associations in this person's feedback, not evidence of treatment efficacy.
    func evidence(for movement: Movement) -> String? {
        let rated = actions.filter { $0.movement == movement && $0.completedAt != nil && $0.outcome != nil }
        guard rated.count >= 3 else { return nil }
        let helped = rated.filter { $0.outcome == .better }.count
        return "You felt better after \(helped) of \(rated.count) \(movement.title.lowercased()) check-ins. A small personal sample, not a guarantee."
    }
    var suggestedMovement: Movement {
        let preferred = preferences.movement
        let preferredRatings = actions.filter { $0.movement == preferred && $0.outcome != nil }
        // Only offer an alternative after repeated negative feedback, and explain it in the UI.
        guard preferredRatings.filter({ $0.outcome == .worse }).count >= 3 else { return preferred }
        return Movement.allCases.first { candidate in
            candidate != preferred && actions.filter { $0.movement == candidate && $0.outcome == .better }.count >= 3
        } ?? preferred
    }
    private struct Saved: Codable {
        let checkIn: EnergyCheckIn?
        let actions: [PlannedAction]
    }
    private func persist() {
        guard !isSample else { return }
        do {
            let data = try JSONEncoder().encode(Saved(checkIn: checkIn, actions: actions))
            defaults.set(data, forKey: "daily.support.v1")
        } catch { problem = "Your changes could not be saved. Please try again." }
    }
}

struct RescueProposal: Identifiable {
    let id = UUID()
    let original: PlannedAction?
    let replacement: PlannedAction
    let reason: String
    let bedtime: Date
}

enum RescuePlanner {
    static func propose(original: PlannedAction?, busy: [DateInterval], movement: Movement,
                        minutes: Int, preferences: PlanningPreferences, now: Date,
                        energy: ReportedEnergy?) -> RescueProposal? {
        let duration = TimeInterval(min(max(minutes, 5), 60) * 60)
        let bedtime = preferences.bedtime(on: now)
        guard bedtime > now else { return nil }
        let calendar = Calendar.current
        // Align to the next five-minute boundary, without excluding an exactly aligned time.
        let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let offset = (5 - calendar.component(.minute, from: minute) % 5) % 5
        var start = minute.addingTimeInterval(Double(offset) * 60)
        if start < now { start.addTimeInterval(300) }
        while start.addingTimeInterval(duration) <= bedtime {
            let end = start.addingTimeInterval(duration)
            if !busy.contains(where: { $0.start < end && $0.end > start }) {
                let title = movement == .strength && !preferences.hasEquipment ? "Bodyweight strength" : movement.title
                let action = PlannedAction(eventID: original?.eventID, movement: movement, title: title,
                                           start: start, end: end, beforeTitle: original?.title,
                                           reportedEnergy: energy, isRescue: true)
                let why = energy == .low ? "You said your energy is low. This shorter option fits a free gap and ends before bedtime."
                    : "This option fits the time you chose, keeps your fixed commitments, and ends before bedtime."
                return RescueProposal(original: original, replacement: action, reason: why, bedtime: bedtime)
            }
            start.addTimeInterval(300)
        }
        return nil
    }
}

enum SampleDay {
    static func at(_ hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
    static var now: Date { at(14) }
    static var history: [DaySignals] {
        (0...14).map { day in
            DaySignals(date: Calendar.current.date(byAdding: .day, value: -day, to: at(0))!,
                       asleepMinutes: day == 0 ? 340 : Double(420 + (day % 4) * 10),
                       efficiency: day == 0 ? 86 : 95, deepMinutes: Double(55 + day % 5),
                       remMinutes: Double(75 + day % 7), restingHR: Double(60 + day % 4))
        }
    }
}

/// Deliberately narrow: normal calendar requests still use the existing confirmed tools.
enum RescueIntent {
    struct Request { let minutes: Int? }
    static func parse(_ text: String) -> Request? {
        let lower = text.lowercased()
        guard lower.contains("rescue my day") || lower.contains("replan my day") ||
              ((lower.contains("tired") || lower.contains("exhausted")) && lower.contains("minutes")) else { return nil }
        let regex = try? NSRegularExpression(pattern: #"\b(5|10|15|20|30|45|60)\s*(?:minutes|mins|minute)\b"#)
        let range = NSRange(lower.startIndex..., in: lower)
        let match = regex?.firstMatch(in: lower, range: range)
        let minutes = match.flatMap { Range($0.range(at: 1), in: lower) }.flatMap { Int(lower[$0]) }
        return Request(minutes: minutes)
    }
}
