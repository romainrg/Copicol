import Foundation

/// Durée de conservation des éléments non épinglés, comptée depuis leur dernière utilisation.
public enum RetentionPolicy: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month
    case unlimited

    public var interval: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .unlimited: nil
        }
    }

    /// Date en deçà de laquelle un élément non épinglé est purgé ; nil = aucune purge.
    public func cutoff(from now: Date) -> Date? {
        interval.map { now.addingTimeInterval(-$0) }
    }
}
