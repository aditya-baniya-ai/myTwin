import Foundation

/// One day the user rated, with the sleep signals from that morning.
struct EnergyEntry: Codable {
    let date: Date
    let rating: Double            // 1...5, what the user said
    let features: [String: Double]
}

/// Keeps the user's own energy ratings on the phone and learns their personal weights
/// from them. Nothing is uploaded: the file lives in the app's own container.
@MainActor
@Observable
final class EnergyDiary {
    /// Ratings needed before personal weights carry half the decision.
    static let blendPoint = 20.0
    /// Fixed ridge penalty: with a few dozen ratings, cross-validating on device would
    /// overfit the little data there is.
    static let penalty = 10.0
    /// Ratings needed before a personal fit is attempted at all.
    static let minimumRatings = 10

    private(set) var entries: [EnergyEntry] = []

    private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "energy_diary.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([EnergyEntry].self, from: data) {
            entries = saved
        }
    }

    var ratingCount: Int { entries.count }

    func ratedToday(_ calendar: Calendar = .current) -> Bool {
        entries.contains { calendar.isDateInToday($0.date) }
    }

    func record(rating: Double, features: [String: Double], date: Date = .now) {
        let calendar = Calendar.current
        entries.removeAll { calendar.isDate($0.date, inSameDayAs: date) }   // one rating per day
        entries.append(EnergyEntry(date: date, rating: rating, features: features))
        entries.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL) }
    }

    /// The user's own average rating, which personal predictions are measured against.
    var averageRating: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + $1.rating } / Double(entries.count)
    }

    /// Weights fitted to this user's own ratings, predicting how far a day sits from
    /// their average. Ridge regression solved directly: five features is a 6x6 system.
    func personalFit(featureOrder: [String]) -> (intercept: Double, weights: [Double])? {
        guard entries.count >= Self.minimumRatings, let average = averageRating else { return nil }

        var rows: [[Double]] = []
        var targets: [Double] = []
        for entry in entries {
            var row = [1.0]                                  // intercept column
            var complete = true
            for name in featureOrder {
                guard let value = entry.features[name] else { complete = false; break }
                row.append(value)
            }
            guard complete else { continue }
            rows.append(row)
            targets.append(entry.rating - average)
        }
        guard rows.count >= Self.minimumRatings else { return nil }

        let width = featureOrder.count + 1
        var normal = Array(repeating: Array(repeating: 0.0, count: width), count: width)
        var righthand = Array(repeating: 0.0, count: width)
        for (row, target) in zip(rows, targets) {
            for i in 0..<width {
                righthand[i] += row[i] * target
                for j in 0..<width { normal[i][j] += row[i] * row[j] }
            }
        }
        for i in 1..<width { normal[i][i] += Self.penalty }   // the intercept is not penalised

        guard let solution = solve(normal, righthand) else { return nil }
        return (solution[0], Array(solution.dropFirst()))
    }

    /// How much to trust the personal fit, 0...1, growing with the number of ratings.
    var personalShare: Double {
        Double(entries.count) / (Double(entries.count) + Self.blendPoint)
    }

    /// Gaussian elimination with partial pivoting.
    private func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        var a = matrix
        var b = vector
        let n = b.count

        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row][column]) > abs(a[pivot][column]) {
                pivot = row
            }
            guard abs(a[pivot][column]) > 1e-10 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)

            for row in (column + 1)..<n {
                let factor = a[row][column] / a[column][column]
                guard factor != 0 else { continue }
                for col in column..<n { a[row][col] -= factor * a[column][col] }
                b[row] -= factor * b[column]
            }
        }

        var solution = Array(repeating: 0.0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var value = b[row]
            for col in (row + 1)..<n { value -= a[row][col] * solution[col] }
            solution[row] = value / a[row][row]
        }
        return solution
    }
}
