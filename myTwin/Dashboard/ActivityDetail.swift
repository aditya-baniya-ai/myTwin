import SwiftUI

/// Extended activity detail cards shown only in the Activity detail tab, below the
/// summary ActivityGrid. These display heart rate, flights climbed, distance, workouts,
/// nutrition (MyFitnessPal), and body metrics that aren't in the summary grid.
struct ActivityDetail: View {
    let snapshot: HealthSnapshot
    let workouts: [WorkoutDetail]

    private static let heartColors = [Color(red: 1.00, green: 0.30, blue: 0.40), Color(red: 1.00, green: 0.55, blue: 0.65)]
    private static let flightColors = [Color(red: 0.95, green: 0.70, blue: 0.20), Color(red: 1.00, green: 0.85, blue: 0.40)]
    private static let distColors = [Color(red: 0.30, green: 0.78, blue: 1.00), Color(red: 0.55, green: 0.90, blue: 1.00)]
    private static let nutritionColors = [Color(red: 0.52, green: 0.44, blue: 0.99), Color(red: 0.75, green: 0.60, blue: 1.00)]

    var body: some View {
        VStack(spacing: 14) {
            // -- Heart & Body --
            heartAndBodySection

            // -- Movement --
            movementSection

            // -- Today's workouts --
            if !workouts.isEmpty {
                workoutsSection
            }

            // -- Nutrition (MyFitnessPal / Health) --
            if hasNutritionData {
                nutritionSection
            }
        }
    }

    // MARK: - Heart & Body

    private var heartAndBodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Heart & Body", symbol: "heart.fill", tint: Self.heartColors[0])

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metricTile("Heart Rate", value: snapshot.heartRate.map { "\(Int($0))" },
                           unit: "bpm", symbol: "heart.fill", tint: Self.heartColors[0])
                metricTile("Resting HR", value: snapshot.restingHR.map { "\(Int($0))" },
                           unit: "bpm", symbol: "heart.circle", tint: Self.heartColors[0])
                metricTile("HRV", value: snapshot.hrvMs.map { "\(Int($0))" },
                           unit: "ms", symbol: "waveform.path.ecg", tint: Self.heartColors[1],
                           detail: "stress indicator")
                metricTile("VO\u{2082} Max", value: snapshot.vo2Max.map { String(format: "%.1f", $0) },
                           unit: "mL/kg/min", symbol: "lungs.fill", tint: Self.distColors[0])
                metricTile("Respiratory", value: snapshot.respiratoryRate.map { String(format: "%.1f", $0) },
                           unit: "br/min", symbol: "wind", tint: Self.distColors[1])
                if let mindful = snapshot.mindfulMinutes {
                    metricTile("Mindful", value: String(format: "%.0f", mindful),
                               unit: "min", symbol: "brain.head.profile", tint: Color(red: 0.55, green: 0.85, blue: 0.65))
                }
            }
        }
        .dashboardCard()
    }

    // MARK: - Movement

    private var movementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Movement", symbol: "figure.walk", tint: Self.flightColors[0])

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metricTile("Flights", value: snapshot.flightsClimbed.map { "\(Int($0))" },
                           unit: "climbed", symbol: "arrow.up.right", tint: Self.flightColors[0])
                metricTile("Distance", value: snapshot.distanceKm.map { String(format: "%.1f", $0) },
                           unit: "km", symbol: "figure.walk.motion", tint: Self.distColors[0])
                if let standHours = snapshot.standHours {
                    metricTile("Stand", value: "\(standHours)",
                               unit: "hours", symbol: "figure.stand", tint: Color(red: 0.35, green: 0.90, blue: 0.45))
                }
            }
        }
        .dashboardCard()
    }

    // MARK: - Workouts

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Today's Workouts", symbol: "dumbbell.fill", tint: Self.heartColors[0])

            ForEach(workouts) { workout in
                HStack(spacing: 12) {
                    Image(systemName: workoutIcon(workout.type))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Self.heartColors[0])
                        .frame(width: 36, height: 36)
                        .background(Self.heartColors[0].opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.type)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Label(String(format: "%.0f min", workout.durationMinutes),
                                  systemImage: "clock")
                            if let cal = workout.caloriesBurned {
                                Label("\(Int(cal)) kcal", systemImage: "flame.fill")
                            }
                            if let dist = workout.distanceKm, dist > 0 {
                                Label(String(format: "%.1f km", dist), systemImage: "arrow.right")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(workout.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if workout.id != workouts.last?.id {
                    Divider()
                }
            }
        }
        .dashboardCard()
    }

    // MARK: - Nutrition

    private var hasNutritionData: Bool {
        [snapshot.dietaryEnergy, snapshot.protein, snapshot.carbs, snapshot.fat].contains { $0 != nil }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Nutrition", symbol: "fork.knife", tint: Self.nutritionColors[0])

            if let energy = snapshot.dietaryEnergy {
                HStack {
                    Text("Calories consumed")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(energy)) kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Self.nutritionColors[0])
                }
            }

            // Macro bars
            let macros: [(String, Double?, Color)] = [
                ("Protein", snapshot.protein, Color(red: 0.30, green: 0.78, blue: 1.00)),
                ("Carbs", snapshot.carbs, Color(red: 0.95, green: 0.70, blue: 0.20)),
                ("Fat", snapshot.fat, Color(red: 1.00, green: 0.45, blue: 0.55)),
            ]

            ForEach(macros.filter { $0.1 != nil }, id: \.0) { name, grams, color in
                if let g = grams {
                    macroRow(name, grams: g, color: color)
                }
            }

            // Extras
            let extras: [(String, Double?, String, String)] = [
                ("Sugar", snapshot.sugar, "g", "cube"),
                ("Fiber", snapshot.fiber, "g", "leaf.fill"),
                ("Water", snapshot.water, "L", "drop.fill"),
            ]

            let available = extras.filter { $0.1 != nil }
            if !available.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    ForEach(available, id: \.0) { name, value, unit, symbol in
                        if let v = value {
                            VStack(spacing: 2) {
                                Image(systemName: symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: v < 10 ? "%.1f" : "%.0f", v))
                                    .font(.subheadline.weight(.bold))
                                Text("\(unit) \(name.lowercased())")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .dashboardCard()
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
    }

    private func metricTile(_ title: String, value: String?, unit: String, symbol: String,
                            tint: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value ?? "—")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Text(unit)
                if let detail {
                    Text("·")
                    Text(detail)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
    }

    private func macroRow(_ name: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.caption.weight(.medium))
                .frame(width: 55, alignment: .leading)
            GeometryReader { geo in
                let maxGrams: Double = name == "Protein" ? 150 : name == "Carbs" ? 300 : 100
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [color, color.opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(grams / maxGrams, 1))
                    }
            }
            .frame(height: 12)
            Text(String(format: "%.0fg", grams))
                .font(.caption.weight(.semibold))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func workoutIcon(_ type: String) -> String {
        switch type {
        case "Running": "figure.run"
        case "Walking": "figure.walk"
        case "Cycling": "figure.outdoor.cycle"
        case "Swimming": "figure.pool.swim"
        case "Yoga": "figure.yoga"
        case "Strength Training": "dumbbell.fill"
        case "HIIT": "bolt.heart.fill"
        case "Hiking": "figure.hiking"
        case "Dance": "figure.dance"
        default: "figure.mixed.cardio"
        }
    }
}
