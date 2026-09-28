import EventKit
import SwiftUI

/// Everything the guest demo shows instead of your own data: a fictional person's health,
/// workouts, weight, a week of calendar and the questions they ask. Times hang off today,
/// so the demo never looks out of date. Nothing here is read from or written to HealthKit,
/// Calendar or the real settings.
enum DemoData {
    // MARK: - Health

    /// Today so far, at the demo's 2 PM. Sleep matches last night in `SampleDay.history`.
    static var snapshot: HealthSnapshot {
        var value = HealthSnapshot()
        value.sleepHours = 340 / 60
        value.restingHR = 63
        value.hrvMs = 42
        value.respiratoryRate = 14.8
        value.heartRate = 74
        value.steps = 6_420
        value.activeEnergyKcal = 318
        value.distanceKm = 4.9
        value.flightsClimbed = 7
        value.standHours = 8
        value.mindfulMinutes = 10
        value.vo2Max = 44.6
        value.dietaryEnergy = 1_340
        value.protein = 72
        value.carbs = 150
        value.fat = 48
        value.water = 1.4
        return value
    }

    /// A light walk before work. Not counted as training, so the plan still suggests some.
    static var workouts: [WorkoutDetail] {
        [WorkoutDetail(id: UUID(), type: "Walking", start: SampleDay.at(7, minute: 10),
                       end: SampleDay.at(7, minute: 40), durationMinutes: 30,
                       caloriesBurned: 112, distanceKm: 2.4)]
    }

    /// Three months of weigh-ins, drifting gently down.
    static var weights: [WeightSample] {
        (0..<30).reversed().map { step in
            let date = Calendar.current.date(byAdding: .day, value: -step * 3, to: SampleDay.at(7)) ?? .now
            return WeightSample(date: date, pounds: 168.4 + Double(step) * 0.12 + (step % 3 == 0 ? 0.4 : 0))
        }
    }

    /// Days with each kind of data in the last 90, for "What myTwin can read".
    static let coverage = ["Sleep": 88, "Resting heart rate": 90, "Heart rate variability": 61,
                           "Steps": 90, "Active energy": 90]

    // MARK: - Calendar

    private struct Entry {
        let day: Int                  // 0 is today
        let title: String
        let start: (Int, Int)
        let minutes: Int
        let kind: Kind
        var allDay = false
    }

    private enum Kind: CaseIterable {
        case work, personal, school, fitness
        var name: String {
            switch self { case .work: "Work"; case .personal: "Personal"; case .school: "School"; case .fitness: "Fitness" }
        }
        var color: CGColor {
            switch self {
            case .work: UIColor.systemBlue.cgColor
            case .personal: UIColor.systemPink.cgColor
            case .school: UIColor.systemPurple.cgColor
            case .fitness: UIColor.systemOrange.cgColor
            }
        }
    }

    private static let entries: [Entry] = [
        Entry(day: 0, title: "Morning standup", start: (9, 0), minutes: 30, kind: .work),
        Entry(day: 0, title: "Lunch with Priya", start: (12, 0), minutes: 45, kind: .personal),
        Entry(day: 0, title: "Project meeting", start: (14, 30), minutes: 30, kind: .work),
        Entry(day: 0, title: "Class", start: (16, 0), minutes: 60, kind: .school),
        Entry(day: 1, title: "Team standup", start: (9, 30), minutes: 15, kind: .work),
        Entry(day: 1, title: "Dentist", start: (10, 0), minutes: 45, kind: .personal),
        Entry(day: 1, title: "Gym: legs", start: (18, 0), minutes: 75, kind: .fitness),
        Entry(day: 2, title: "Run club", start: (8, 0), minutes: 60, kind: .fitness),
        Entry(day: 2, title: "Client call", start: (13, 0), minutes: 60, kind: .work),
        Entry(day: 2, title: "Study group", start: (15, 0), minutes: 90, kind: .school),
        Entry(day: 3, title: "Mom's birthday", start: (0, 0), minutes: 0, kind: .personal, allDay: true),
        Entry(day: 3, title: "Team standup", start: (9, 30), minutes: 15, kind: .work),
        Entry(day: 3, title: "Dinner with Sam", start: (19, 0), minutes: 120, kind: .personal),
        Entry(day: 4, title: "Sprint demo", start: (11, 0), minutes: 60, kind: .work),
        Entry(day: 4, title: "Yoga", start: (17, 30), minutes: 60, kind: .fitness),
        Entry(day: 5, title: "Farmers market", start: (10, 0), minutes: 90, kind: .personal),
        Entry(day: 5, title: "Soccer game", start: (15, 0), minutes: 120, kind: .fitness),
        Entry(day: 6, title: "Long run", start: (9, 0), minutes: 90, kind: .fitness),
        Entry(day: 6, title: "Plan the week", start: (20, 0), minutes: 30, kind: .personal),
    ]

    /// The week's events as in-memory calendar events, never saved to `store`.
    @MainActor
    static func events(in store: EKEventStore) -> [EKEvent] {
        var calendars: [Kind: EKCalendar] = [:]
        for kind in Kind.allCases {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = kind.name
            calendar.cgColor = kind.color
            calendars[kind] = calendar
        }
        let days = Calendar.current
        let today = days.startOfDay(for: .now)
        return entries.compactMap { entry in
            guard let day = days.date(byAdding: .day, value: entry.day, to: today),
                  let start = days.date(bySettingHour: entry.start.0, minute: entry.start.1, second: 0, of: day)
            else { return nil }
            let event = EKEvent(eventStore: store)
            event.title = entry.title
            event.calendar = calendars[entry.kind]
            event.isAllDay = entry.allDay
            event.startDate = start
            event.endDate = entry.allDay ? days.date(byAdding: .day, value: 1, to: day) ?? start
                                         : start.addingTimeInterval(TimeInterval(entry.minutes * 60))
            return event
        }
    }

    // MARK: - Questions

    /// What the demo person keeps asking, with Dash's last answers, for "You often ask".
    static var questions: [AskedQuestions.Asked] {
        let now = Date.now
        return [
            .init(question: "How did I sleep last night", count: 6, last: now.addingTimeInterval(-3_600),
                  answer: "5.7 hours, about an hour and a half under your usual 7.2, so today runs below your normal."),
            .init(question: "When should I work out today", count: 4, last: now.addingTimeInterval(-7_200),
                  answer: "Your 5 PM strength session lands on your dip. A 20-minute walk at 2 PM fits better; lift tomorrow morning."),
            .init(question: "What do I have tomorrow", count: 3, last: now.addingTimeInterval(-86_400),
                  answer: "Team standup at 9:30, the dentist at 10, and the gym at 6 PM."),
            .init(question: "When is my energy lowest today", count: 2, last: now.addingTimeInterval(-90_000),
                  answer: "Around 5 PM, at about 39%. Keep that hour light."),
        ]
    }
}
