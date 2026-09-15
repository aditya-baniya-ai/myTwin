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

@MainActor
@Observable
final class HealthManager {
    private let store = HKHealthStore()

    var isAuthorized = false
    var snapshot = HealthSnapshot()
    var errorMessage: String?

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.respiratoryRate),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKCategoryType(.sleepAnalysis),
    ]

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
