import Foundation
import HealthKit

/// Snapshot of the signals the energy model will use.
struct HealthSnapshot {
    var hrvMs: Double?             // latest SDNN (last 24h avg)
    var restingHR: Double?         // bpm, latest
    var respiratoryRate: Double?   // breaths/min, last 24h avg
    var sleepHours: Double?        // asleep time last night (6pm → noon)
    var steps: Double?             // today so far
    var activeEnergyKcal: Double?  // today so far
}

/// One weigh-in from Apple Health.
struct WeightSample: Identifiable {
    let date: Date
    let pounds: Double
    var id: Date { date }
}

@MainActor
@Observable
final class HealthManager {
    private let store = HKHealthStore()

    var isAuthorized = false
    var snapshot = HealthSnapshot()
    var errorMessage: String?

    private let coreTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.respiratoryRate),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKCategoryType(.sleepAnalysis),
    ]
    /// Added after launch. Kept apart so people who already connected are asked only about it.
    private var readTypes: Set<HKObjectType> {
        coreTypes.union([HKQuantityType(.bodyMass), HKObjectType.workoutType()])
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // HealthKit never reveals whether *read* access was granted (privacy);
            // denied types simply return no samples.
            isAuthorized = true
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// HealthKit never reveals whether read access was granted, but it does say whether we have
    /// already asked. Without this the app would show "Connect Apple Health" again on every launch.
    func refreshAuthorizationState() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let core = try? await store.statusForAuthorizationRequest(toShare: [], read: coreTypes)
        guard core == .unnecessary else { return }      // never connected: wait for the button
        if (try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)) == .shouldRequest {
            // Something new to read since you connected (weight): iOS asks only about that.
            try? await store.requestAuthorization(toShare: [], read: readTypes)
        }
        isAuthorized = true
        await refresh()
    }

    /// Asks HealthKit to wake the app whenever new sleep, heart or weight data arrives,
    /// so the twin is worked out before you open anything. Registered once at launch; iOS
    /// then launches the app in the background to run `arrived`.
    func watchForNewData(_ arrived: @escaping @Sendable () async -> Void) {
        let watched: [HKSampleType] = [HKCategoryType(.sleepAnalysis),
                                       HKQuantityType(.restingHeartRate),
                                       HKQuantityType(.bodyMass)]
        for type in watched {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, done, _ in
                Task {
                    await arrived()
                    done()                  // tells iOS the wake-up is finished
                }
            }
            store.execute(observer)
        }
    }

    /// Saves a weigh-in to Apple Health, asking to write weight the first time.
    func logWeight(pounds: Double, at date: Date = .now) async throws {
        let type = HKQuantityType(.bodyMass)
        if store.authorizationStatus(for: type) != .sharingAuthorized {
            try await store.requestAuthorization(toShare: [type], read: readTypes)
        }
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw HealthError.cantSaveWeight
        }
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        try await store.save(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
    }

    enum HealthError: LocalizedError {
        case cantSaveWeight
        var errorDescription: String? {
            "myTwin isn't allowed to save weight. Turn it on in Settings › Health › Data Access & Devices › myTwin."
        }
    }

    /// Workouts recorded today, so the plan can tell whether you actually trained rather
    /// than guessing from what's written in your calendar.
    func workoutsToday() async -> [DateInterval] {
        let start = Calendar.current.startOfDay(for: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        return workouts.map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    /// Weigh-ins from the last `days` days, oldest first, in pounds.
    func weights(days: Int = 90) async -> [WeightSample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { WeightSample(date: $0.startDate, pounds: $0.quantity.doubleValue(for: .pound())) }
    }

    /// Today's health numbers as plain text, for the chatbot to read.
    func summaryText() async -> String {
        guard isAuthorized else {
            return "Health data isn't connected. The user can tap Connect Apple Health on the home screen."
        }
        await refresh()

        var lines: [String] = []
        if let value = snapshot.sleepHours { lines.append("Sleep last night: \(String(format: "%.1f", value)) hours") }
        if let value = snapshot.hrvMs { lines.append("HRV (24h average): \(String(format: "%.0f", value)) ms") }
        if let value = snapshot.restingHR { lines.append("Resting heart rate: \(String(format: "%.0f", value)) bpm") }
        if let value = snapshot.respiratoryRate { lines.append("Respiratory rate: \(String(format: "%.1f", value)) breaths per minute") }
        if let value = snapshot.steps { lines.append("Steps today: \(String(format: "%.0f", value))") }
        if let value = snapshot.activeEnergyKcal { lines.append("Active energy today: \(String(format: "%.0f", value)) kcal") }

        return lines.isEmpty ? "No health data has been recorded yet." : lines.joined(separator: "\n")
    }

    func refresh() async {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)
        let startOfToday = Calendar.current.startOfDay(for: now)

        async let hrv = average(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: dayAgo, to: now)
        async let rhr = mostRecent(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let resp = average(.respiratoryRate, unit: .count().unitDivided(by: .minute()), from: dayAgo, to: now)
        async let steps = sum(.stepCount, unit: .count(), from: startOfToday, to: now)
        async let energy = sum(.activeEnergyBurned, unit: .kilocalorie(), from: startOfToday, to: now)
        async let sleep = lastNightSleepHours()

        snapshot = HealthSnapshot(
            hrvMs: await hrv,
            restingHR: await rhr,
            respiratoryRate: await resp,
            sleepHours: await sleep,
            steps: await steps,
            activeEnergyKcal: await energy
        )
    }

    // MARK: - What this phone actually has

    /// How many of the last `days` days hold data for each signal. Answers the question
    /// "can this app work for me at all", which no amount of guessing can.
    func coverage(days: Int = 90) async -> [String: Int] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now))
        else { return [:] }

        async let sleep = sleepDayCount(from: start)
        async let resting = dayCount(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: start)
        async let hrv = dayCount(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start)
        async let steps = dayCount(.stepCount, unit: .count(), from: start, cumulative: true)
        async let energy = dayCount(.activeEnergyBurned, unit: .kilocalorie(), from: start, cumulative: true)

        return await ["Sleep": sleep, "Resting heart rate": resting,
                      "Heart rate variability": hrv, "Steps": steps, "Active energy": energy]
    }

    private func sleepDayCount(from start: Date) async -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return 0 }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let calendar = Calendar.current
        let days = samples.filter { asleep.contains($0.value) }
            .map { calendar.startOfDay(for: $0.endDate) }
        return Set(days).count
    }

    private func dayCount(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date,
                          cumulative: Bool = false) async -> Int {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return 0 }

        var count = 0
        collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
            let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            if let value = quantity?.doubleValue(for: unit), value > 0 { count += 1 }
        }
        return count
    }

    // MARK: - History for the energy model

    /// Looks back further when nights are sparse. Most people do not wear a watch every
    /// night, and Garmin only syncs forward from the day you connect it, so a fixed
    /// two-week window often finds nothing at all.
    func history(minimumNights: Int = 7) async -> (days: [DaySignals], searchedDays: Int) {
        let spans = [60, 180, 365]
        for span in spans {
            let days = await dailyHistory(days: span)
            let nights = days.dropFirst().filter { $0.asleepMinutes != nil }.count
            if nights >= minimumNights || span == spans.last {
                return (days, span)
            }
        }
        return ([], spans.last ?? 365)
    }

    /// One entry per day, most recent first, holding the signals the energy model compares
    /// against your own baseline. Sleep is counted from 6pm the evening before to noon.
    func dailyHistory(days: Int) async -> [DaySignals] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let spanStart = calendar.date(byAdding: .day, value: -(days + 1), to: today) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: spanStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        let restingByDay = await restingHeartRateByDay(from: spanStart)

        // Bucket every sample once, so looking back a year stays cheap. A night is filed
        // under the morning it ends: shifting by six hours puts evening and small-hours
        // sleep on the same day.
        var byNight: [Date: [HKCategorySample]] = [:]
        for sample in samples {
            let night = calendar.startOfDay(for: sample.startDate.addingTimeInterval(6 * 3600))
            byNight[night, default: []].append(sample)
        }

        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let deepValue = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let remValue = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        let awakeValue = HKCategoryValueSleepAnalysis.awake.rawValue
        let inBedValue = HKCategoryValueSleepAnalysis.inBed.rawValue

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var signals = DaySignals(date: day)
            signals.restingHR = restingByDay[day]

            guard let night = byNight[day], !night.isEmpty else { return signals }
            let asleep = minutes(of: night.filter { asleepValues.contains($0.value) })
            let awake = minutes(of: night.filter { $0.value == awakeValue })
            let inBed = minutes(of: night.filter { $0.value == inBedValue })

            if let firstAsleep = night.filter({ asleepValues.contains($0.value) })
                .min(by: { $0.startDate < $1.startDate }) {
                let parts = calendar.dateComponents([.hour, .minute], from: firstAsleep.startDate)
                signals.bedHour = Double(parts.hour ?? 23) + Double(parts.minute ?? 0) / 60
            }
            signals.asleepMinutes = asleep > 0 ? asleep : nil
            signals.deepMinutes = minutes(of: night.filter { $0.value == deepValue })
            signals.remMinutes = minutes(of: night.filter { $0.value == remValue })

            // Apple Watch often records no "in bed" time, so fall back to asleep + awake.
            let denominator = inBed > 0 ? inBed : asleep + awake
            if asleep > 0, denominator > 0 { signals.efficiency = 100 * asleep / denominator }
            return signals
        }
    }

    /// When this person usually falls asleep, from their own nights. Falls back to 11pm.
    /// Returned as (hour, minute) so a reminder can be scheduled against it.
    func typicalBedtime(from history: [DaySignals]) -> (hour: Int, minute: Int) {
        let hours = history.compactMap(\.bedHour)
            // Past midnight reads as 0-3, which would drag the average back to morning.
            .map { $0 < 12 ? $0 + 24 : $0 }
            .sorted()
        guard !hours.isEmpty else { return (23, 0) }

        let middle = hours[hours.count / 2]
        let wrapped = middle >= 24 ? middle - 24 : middle
        return (Int(wrapped), Int((wrapped - wrapped.rounded(.down)) * 60))
    }

    /// Overlapping samples are merged, because the watch and phone can both record a night.
    private func minutes(of samples: [HKCategorySample]) -> Double {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for sample in sorted {
            if let open = current, sample.startDate <= open.end {
                current = (open.start, max(open.end, sample.endDate))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = (sample.startDate, sample.endDate)
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total / 60
    }

    private func restingHeartRateByDay(from start: Date) async -> [Date: Double] {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.restingHeartRate), predicate: predicate),
            options: .discreteAverage,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }

        var byDay: [Date: Double] = [:]
        let unit = HKUnit.count().unitDivided(by: .minute())
        collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
            if let value = statistics.averageQuantity()?.doubleValue(for: unit) {
                byDay[calendar.startOfDay(for: statistics.startDate)] = value
            }
        }
        return byDay
    }

    // MARK: - Queries

    private func statistics(_ id: HKQuantityTypeIdentifier, options: HKStatisticsOptions,
                            from start: Date, to end: Date) async -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: options
        )
        return try? await descriptor.result(for: store)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await statistics(id, options: .cumulativeSum, from: from, to: to)?.sumQuantity()?.doubleValue(for: unit)
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await statistics(id, options: .discreteAverage, from: from, to: to)?.averageQuantity()?.doubleValue(for: unit)
    }

    private func mostRecent(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try? await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    private func lastNightSleepHours() async -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .hour, value: -6, to: today)!   // 6pm yesterday
        let end = cal.date(byAdding: .hour, value: 12, to: today)!     // noon today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }

        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard !asleep.isEmpty else { return nil }

        // Watch + iPhone can both write sleep; merge overlapping intervals to avoid double counting.
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for s in asleep {
            if let c = current, s.startDate <= c.end {
                current = (c.start, max(c.end, s.endDate))
            } else {
                if let c = current { total += c.end.timeIntervalSince(c.start) }
                current = (s.startDate, s.endDate)
            }
        }
        if let c = current { total += c.end.timeIntervalSince(c.start) }
        return total / 3600
    }
}
