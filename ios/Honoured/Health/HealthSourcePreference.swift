import Foundation

struct HealthSourceDescriptor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case appleWatch = "apple_watch"
        case iPhone = "iphone"
        case otherWatch = "other_watch"
        case other
    }

    let id: String
    let name: String
    let bundleIdentifier: String
    let kind: Kind

    static func make(name: String, bundleIdentifier: String) -> HealthSourceDescriptor {
        let normalized = "\(name) \(bundleIdentifier)".lowercased()
        let kind: Kind
        if normalized.contains("apple watch") || normalized.contains("watchkit") {
            kind = .appleWatch
        } else if normalized.contains("iphone") || normalized.contains("healthapp") {
            kind = .iPhone
        } else if normalized.contains("watch") || normalized.contains("garmin") || normalized.contains("fitbit") {
            kind = .otherWatch
        } else {
            kind = .other
        }
        return HealthSourceDescriptor(
            id: "\(bundleIdentifier)|\(name)",
            name: name,
            bundleIdentifier: bundleIdentifier,
            kind: kind
        )
    }
}

enum HealthSourcePreference: Equatable, Sendable {
    case automatic
    case source(String)

    var payload: [String: String] {
        switch self {
        case .automatic: return ["mode": "automatic"]
        case .source(let id): return ["mode": "source", "sourceId": id]
        }
    }

    static func parse(mode: Any?, sourceId: Any?) -> HealthSourcePreference? {
        switch mode as? String {
        case "automatic": return .automatic
        case "source":
            guard let id = sourceId as? String, !id.isEmpty else { return nil }
            return .source(id)
        default: return nil
        }
    }
}

struct HealthSourceResolution: Equatable, Sendable {
    let selected: HealthSourceDescriptor?
    let requestedSourceMissing: Bool
}

enum HealthSourceSelector {
    static func resolve(
        preference: HealthSourcePreference,
        available: [HealthSourceDescriptor]
    ) -> HealthSourceResolution {
        let sorted = available.sorted {
            if rank($0.kind) != rank($1.kind) { return rank($0.kind) < rank($1.kind) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        switch preference {
        case .automatic:
            return HealthSourceResolution(selected: sorted.first, requestedSourceMissing: false)
        case .source(let id):
            if let source = available.first(where: { $0.id == id }) {
                return HealthSourceResolution(selected: source, requestedSourceMissing: false)
            }
            return HealthSourceResolution(selected: sorted.first, requestedSourceMissing: true)
        }
    }

    private static func rank(_ kind: HealthSourceDescriptor.Kind) -> Int {
        switch kind {
        case .appleWatch: return 0
        case .iPhone: return 1
        case .otherWatch: return 2
        case .other: return 3
        }
    }
}
