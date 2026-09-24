import Foundation

/// What Dash says when you look at him: one line about the day as it actually is, built
/// from the charge, the reading and what's next on your calendar. No model call, so he
/// always has something true to say, online or not.
enum DayGreeting {
    static func line(charge: Double, reading: EnergyReading?, next: (title: String, start: Date)?,
                     dayStart: Double, now: Date = .now, healthConnected: Bool,
                     userName: String? = nil) -> String {
        guard healthConnected else {
            return "Connect Apple Health and I'll tell you how today is going."
        }
        guard reading != nil else {
            return "A few more nights of sleep and I can tell you how today compares with your normal."
        }

        let percent = Int(charge * 100)
        let greeting = if let userName, !userName.isEmpty {
            "\(timeOfDay(now)), \(userName). You're at \(percent)%"
        } else {
            "\(timeOfDay(now)). You're at \(percent)%"
        }

        // Something coming up soon is the most useful thing to say.
        if let next, next.start > now, next.start.timeIntervalSince(now) < 3 * 3600 {
            let then = Int(DayCharge.remaining(from: dayStart, at: next.start) * 100)
            let clock = next.start.formatted(date: .omitted, time: .shortened)
            return "\(greeting). \(next.title) at \(clock), and you'll be at \(then)% by then."
        }

        switch percent {
        case 75...: return "\(greeting) — your best window today, so start with the hard thing."
        case 55..<75: return "\(greeting) — steady. Good for anything that doesn't need a sprint."
        case 35..<55: return "\(greeting) — past your peak. Keep it light and save the heavy stuff."
        default: return "\(greeting) — running low. Wind down and get to bed on time."
        }
    }

    private static func timeOfDay(_ now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case ..<12: "Morning"
        case 12..<17: "Afternoon"
        default: "Evening"
        }
    }
}
