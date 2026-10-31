import Foundation

struct PaceSample: Identifiable, Codable {
    let id: Int
    let elapsedSeconds: Double
    let secondsPerKilometre: Double
    let segment: Int
    let isWarmUp: Bool
}

struct SavedRun: Identifiable, Codable {
    let id: UUID
    let date: Date
    let elapsedSeconds: Double
    let distanceMetres: Double
    let samples: [PaceSample]

    var averagePace: Double? {
        RunHistory.averagePace(seconds: elapsedSeconds, metres: distanceMetres)
    }
}

enum RunHistory {
    static func averagePace(seconds: Double, metres: Double) -> Double? {
        guard seconds > 0, metres > 0 else { return nil }
        return seconds / metres * 1000
    }

    static func load(from file: URL) throws -> [SavedRun] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([SavedRun].self, from: Data(contentsOf: file))
            .sorted { $0.date > $1.date }
    }

    static func save(_ runs: [SavedRun], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(runs).write(to: file, options: .atomic)
    }
}
