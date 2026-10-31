import Foundation

struct HealthSourceDescriptor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case appleWatch = "apple_watch"
        case iPhone = "iphone"
        case otherWatch = "other_watch"
        case other
        /// The iPhone's own pedometer, read through Core Motion rather than
        /// HealthKit.
        case coreMotion = "core_motion"
        /// The Apple Health samples this iPhone recorded itself (Phase 4
        /// M1.5), whatever the device's name.
        case thisIPhone = "this_iphone"
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

    /// Core Motion, listed with the HealthKit sources so the existing source
    /// picker offers it (Phase 3 M2-C). Every HealthKit source id contains
    /// "|", so this reserved id can never name one. The name, shown to the
    /// person in the picker and wherever a total names its source, is the
    /// client's wording.
    static let coreMotionId = "core_motion"
    static let coreMotion = HealthSourceDescriptor(
        id: coreMotionId,
        name: "Core Motion",
        bundleIdentifier: "",
        kind: .coreMotion
    )

    /// "iPhone" in Health & Tracking (Phase 4 M1.5): only the samples Apple's
    /// own Health source recorded on this model of iPhone. Like Core Motion it
    /// is a reserved id that no HealthKit source id (always containing "|")
    /// can match, so a web build that predates it lists and saves it as an
    /// ordinary source.
    static let thisIPhoneId = "this_iphone"
    static let thisIPhone = HealthSourceDescriptor(
        id: thisIPhoneId,
        name: "iPhone",
        bundleIdentifier: "",
        kind: .thisIPhone
    )
}

enum HealthSourcePreference: Equatable, Sendable {
    case automatic
    case source(String)
    /// Core Motion instead of HealthKit. On the wire it is the source
    /// `HealthSourceDescriptor.coreMotionId`, so a web build that predates it
    /// lists, saves and restores it like any other source.
    case coreMotion
    /// The samples this iPhone recorded, sent as the source
    /// `HealthSourceDescriptor.thisIPhoneId` for the same reason.
    case thisIPhone

    var payload: [String: String] {
        switch self {
        case .automatic: return ["mode": "automatic"]
        case .source(let id): return ["mode": "source", "sourceId": id]
        case .coreMotion: return ["mode": "source", "sourceId": HealthSourceDescriptor.coreMotionId]
        case .thisIPhone: return ["mode": "source", "sourceId": HealthSourceDescriptor.thisIPhoneId]
        }
    }

    static func parse(mode: Any?, sourceId: Any?) -> HealthSourcePreference? {
        switch mode as? String {
        case "automatic": return .automatic
        case "source":
            guard let id = sourceId as? String, !id.isEmpty else { return nil }
            switch id {
            case HealthSourceDescriptor.coreMotionId: return .coreMotion
            case HealthSourceDescriptor.thisIPhoneId: return .thisIPhone
            default: return .source(id)
            }
        default: return nil
        }
    }

    /// How totals of the source-selectable metrics are read, so `health_daily`
    /// rows read another way can be told apart and recomputed. Core Motion
    /// without its permission or pedometer, and an iPhone that recorded
    /// nothing, read the combined total and are labelled so. The iPhone basis
    /// names the model, so a new iPhone recomputes the history it can read.
    func dailyBasis(motionReadable: Bool, thisIPhoneModel: String? = nil) -> String {
        switch self {
        case .automatic: return Self.combinedBasis
        case .source(let id): return "source:\(id)"
        case .coreMotion: return motionReadable ? Self.coreMotionBasis : Self.combinedBasis
        case .thisIPhone:
            guard let thisIPhoneModel else { return Self.combinedBasis }
            return "\(HealthSourceDescriptor.thisIPhoneId):\(thisIPhoneModel)"
        }
    }

    static let combinedBasis = "combined"
    static let coreMotionBasis = "core_motion"
}

/// Where a number came from, as `GOAL_REACHED.source` and Icon readings name
/// it. A HealthKit source the person picked is still `healthkit`.
enum HealthReadingSource: String, Sendable {
    case healthKit = "healthkit"
    case coreMotion = "core_motion"
}

struct HealthSourceResolution: Equatable, Sendable {
    let selected: HealthSourceDescriptor?
    let requestedSourceMissing: Bool

    var readingSource: HealthReadingSource {
        selected?.kind == .coreMotion ? .coreMotion : .healthKit
    }

    /// The label an Icon reading carries, so icon_scoring_v4.sql replaces a
    /// day's total when the person moves between the combined total and
    /// this iPhone, instead of keeping the higher of the two.
    var iconSource: IconMeasurementSource {
        switch selected?.kind {
        case .coreMotion?: return .coreMotion
        case .thisIPhone?: return .healthKitIPhone
        default: return .healthKit
        }
    }
}

enum HealthSourceSelector {
    /// `automatic` selects nothing, so reads use the combined Apple Health
    /// total: the number the Health app shows, every device and app merged
    /// with overlaps removed. Picking one device dropped the steps another
    /// recorded, such as a Garmin walk while the iPhone stayed at home. Only a
    /// source the person chose narrows the read; when that source is gone the
    /// combined total is used and `requestedSourceMissing` says so.
    ///
    /// Core Motion is never added to HealthKit: chosen, it replaces the read.
    /// Without its permission or a pedometer it counts as missing, so the
    /// combined total stands in and the fallback is reported. "iPhone" works
    /// the same way: when this iPhone has recorded nothing (Fitness Tracking
    /// off, or no read access) the combined total stands in and says so.
    static func resolve(
        preference: HealthSourcePreference,
        available: [HealthSourceDescriptor],
        motionReadable: Bool = false,
        thisIPhoneReadable: Bool = false
    ) -> HealthSourceResolution {
        switch preference {
        case .automatic:
            return HealthSourceResolution(selected: nil, requestedSourceMissing: false)
        case .source(let id):
            let source = available.first { $0.id == id }
            return HealthSourceResolution(selected: source, requestedSourceMissing: source == nil)
        case .coreMotion:
            return motionReadable
                ? HealthSourceResolution(selected: .coreMotion, requestedSourceMissing: false)
                : HealthSourceResolution(selected: nil, requestedSourceMissing: true)
        case .thisIPhone:
            return thisIPhoneReadable
                ? HealthSourceResolution(selected: .thisIPhone, requestedSourceMissing: false)
                : HealthSourceResolution(selected: nil, requestedSourceMissing: true)
        }
    }
}
