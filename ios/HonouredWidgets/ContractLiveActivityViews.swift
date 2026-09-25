import SwiftUI

// Views for a contract's Live Activity. They take the plain content state, not
// the ActivityKit context, so the unit tests can render every variant.

enum HonouredPalette {
    /// The web app's ink (#F5F0E8), gold (#C9A84C) and near-black background.
    static let ink = Color(red: 0.961, green: 0.941, blue: 0.910)
    static let gold = Color(red: 0.788, green: 0.659, blue: 0.298)
    static let muted = ink.opacity(0.6)
    static let track = ink.opacity(0.16)
    static let background = Color(red: 0.051, green: 0.051, blue: 0.051)
}

/// Lock Screen and banner presentation.
struct ContractLockScreenView: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContractHeader(state: state, isStale: isStale)
            if state.status == .active {
                if let timer = state.timer {
                    TimerRow(timer: timer, contractName: state.contractName, isStale: isStale)
                }
                ForEach(state.health, id: \.activityId) { part in
                    HealthRow(part: part)
                }
                StaleFooter(state: state, isStale: isStale)
            } else {
                ResultRow(state: state)
            }
        }
        .padding(14)
        .foregroundStyle(HonouredPalette.ink)
        // The Lock Screen gives a Live Activity about 160 pt of height; beyond
        // this size a two-slot card with a timer would be cut off.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - Dynamic Island

struct CompactLeadingView: View {
    let state: HonouredLiveActivityState

    @ViewBuilder
    var body: some View {
        if state.status == .active, state.timer == nil, let part = state.displayedHealth {
            ProgressRing(
                fraction: HonouredLiveActivityFormat.progress(value: part.value, target: part.target),
                symbol: HonouredLiveActivityFormat.symbol(forMetric: part.metric),
                reached: part.reached,
                preservesMetricSymbol: true
            )
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: ContractSymbol.leading(for: state))
                .foregroundStyle(HonouredPalette.gold)
                .accessibilityHidden(true)
        }
    }
}

struct CompactTrailingView: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        Group {
            if state.status == .completed {
                Image(systemName: "checkmark")
                    .foregroundStyle(HonouredPalette.gold)
                    .accessibilityLabel("Honoured")
            } else if state.status == .ended {
                Text("Closed").font(.caption).foregroundStyle(HonouredPalette.muted)
            } else if let timer = state.timer {
                if timer.finished {
                    // The timer is done; the contract is not necessarily.
                    Image(systemName: ContractSymbol.timerDone)
                        .foregroundStyle(HonouredPalette.gold)
                        .accessibilityLabel("Time's up")
                } else if isStale && timer.endsAt <= Date() {
                    // At zero, not yet processed by the app: never a check mark.
                    Text("0:00").foregroundStyle(HonouredPalette.muted)
                } else {
                    Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 52)
                }
            } else if let part = state.displayedHealth {
                ShortHealthValue(part: part)
            } else {
                Text("–").foregroundStyle(HonouredPalette.muted)
            }
        }
        .font(.system(.body, design: .rounded).weight(.semibold))
        .foregroundStyle(HonouredPalette.ink)
    }
}

struct MinimalView: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        if state.status != .active {
            Image(systemName: ContractSymbol.leading(for: state))
                .foregroundStyle(state.status == .completed ? HonouredPalette.gold : HonouredPalette.muted)
                .accessibilityLabel(state.status == .completed ? "Honoured" : "Closed")
        } else if let timer = state.timer {
            if timer.finished || (isStale && timer.endsAt <= Date()) {
                Image(systemName: timer.finished ? ContractSymbol.timerDone : ContractSymbol.timer)
                    .foregroundStyle(timer.finished ? HonouredPalette.gold : HonouredPalette.muted)
                    .accessibilityLabel("Time's up")
            } else {
                ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: ContractSymbol.timer).font(.system(size: 9, weight: .bold))
                }
                .progressViewStyle(.circular)
                .tint(HonouredPalette.gold)
            }
        } else if let part = state.displayedHealth {
            ProgressRing(fraction: HonouredLiveActivityFormat.progress(value: part.value, target: part.target), symbol: HonouredLiveActivityFormat.symbol(forMetric: part.metric), reached: part.reached)
        } else {
            Image(systemName: ContractSymbol.timer).foregroundStyle(HonouredPalette.gold)
        }
    }
}

struct ExpandedLeadingView: View {
    let state: HonouredLiveActivityState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ContractSymbol.leading(for: state))
                .foregroundStyle(HonouredPalette.gold)
                .accessibilityHidden(true)
            Text(state.contractName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(HonouredPalette.ink)
        .padding(.leading, 4)
    }
}

struct ExpandedTrailingView: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        ContractSummary(state: state, isStale: isStale)
            .padding(.trailing, 4)
    }
}

struct ExpandedBottomView: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.status == .active {
                if let timer = state.timer {
                    TimerRow(timer: timer, contractName: state.contractName, isStale: isStale)
                }
                ForEach(state.health, id: \.activityId) { part in
                    HealthRow(part: part)
                }
                StaleFooter(state: state, isStale: isStale)
            } else {
                ResultRow(state: state)
            }
        }
        .foregroundStyle(HonouredPalette.ink)
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - Parts

enum ContractSymbol {
    static let timer = HonouredLiveActivityFormat.timerSymbol
    static let completed = HonouredLiveActivityFormat.completedSymbol

    static let closed = "clock"
    static let timerDone = "hourglass.bottomhalf.filled"

    static func leading(for state: HonouredLiveActivityState) -> String {
        if state.status == .completed { return completed }
        if state.status == .ended { return closed }
        if let timer = state.timer { return timer.finished ? timerDone : self.timer }
        if let part = state.displayedHealth { return HonouredLiveActivityFormat.symbol(forMetric: part.metric) }
        return self.timer
    }
}

private struct ContractHeader: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ContractSymbol.leading(for: state))
                .foregroundStyle(HonouredPalette.gold)
                .accessibilityHidden(true)
            Text(state.contractName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            ContractSummary(state: state, isStale: isStale)
        }
    }
}

/// Top-right of the card: the countdown, or how many slots are reached.
private struct ContractSummary: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        Group {
            switch state.status {
            case .completed, .ended:
                // The outcome is spelled out in the row below.
                EmptyView()
            case .active:
                if let timer = state.timer, !timer.finished, !(isStale && timer.endsAt <= Date()) {
                    Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                } else if state.health.count > 1 {
                    Text("\(state.reachedCount) of \(state.health.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.reachedCount > 0 ? HonouredPalette.gold : HonouredPalette.muted)
                        .accessibilityLabel("\(state.reachedCount) of \(state.health.count) goals reached")
                }
            }
        }
    }
}

private struct TimerRow: View {
    let timer: HonouredLiveActivityState.TimerPart
    let contractName: String
    let isStale: Bool

    var body: some View {
        if timer.finished || (isStale && timer.endsAt <= Date()) {
            // At zero with the app suspended the finish is not processed yet;
            // say so instead of implying the contract is done.
            Label(
                timer.finished ? "Time's up" : "Time's up · open Honoured",
                systemImage: timer.finished ? ContractSymbol.timerDone : ContractSymbol.timer
            )
            .font(.subheadline)
            .foregroundStyle(timer.finished ? HonouredPalette.gold : HonouredPalette.muted)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if timer.name != contractName {
                    Text(timer.name)
                        .font(.caption)
                        .foregroundStyle(HonouredPalette.muted)
                        .lineLimit(1)
                }
                // The countdown itself is in the summary at the top right.
                ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(HonouredPalette.gold)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(timer.name) timer running")
        }
    }
}

private struct HealthRow: View {
    let part: HonouredLiveActivityState.HealthPart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                    Spacer(minLength: 8)
                    HealthValueText(part: part)
                    check
                }
                // Large text with a long name: the icon and the unit still say
                // which slot this is, and the value stays whole.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    icon
                    HealthValueText(part: part)
                    Spacer(minLength: 4)
                    check
                }
            }
            ProgressBar(fraction: HonouredLiveActivityFormat.progress(value: part.value, target: part.target), reached: part.reached)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            icon
            Text(part.name).font(.subheadline).lineLimit(1)
        }
    }

    private var icon: some View {
        Image(systemName: HonouredLiveActivityFormat.symbol(forMetric: part.metric))
            .font(.caption)
            .foregroundStyle(part.reached ? HonouredPalette.gold : HonouredPalette.muted)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var check: some View {
        if part.reached {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HonouredPalette.gold)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityText: String {
        let target = HonouredLiveActivityFormat.targetText(part.target, metric: part.metric, displayUnit: part.displayUnit)
        guard let value = part.value else { return "\(part.name), \(target), no reading yet" }
        let shown = HonouredLiveActivityFormat.valueText(value, metric: part.metric, displayUnit: part.displayUnit)
        return "\(part.name), \(shown) of \(target)\(part.reached ? ", reached" : "")"
    }
}

/// "6,240 / 8,000 steps". Unknown is never shown as zero.
private struct HealthValueText: View {
    let part: HonouredLiveActivityState.HealthPart

    var body: some View {
        let target = HonouredLiveActivityFormat.targetText(part.target, metric: part.metric, displayUnit: part.displayUnit)
        Group {
            if let value = part.value {
                (Text(HonouredLiveActivityFormat.valueText(value, metric: part.metric, displayUnit: part.displayUnit))
                    .fontWeight(.semibold)
                 + Text(" / \(target)").foregroundColor(HonouredPalette.muted))
                    .privacySensitive()
            } else {
                switch part.dataStatus {
                case .noData:
                    Text("No data yet · \(target)").foregroundStyle(HonouredPalette.muted)
                case .waiting, .fresh:
                    Text("Waiting for Health · \(target)").foregroundStyle(HonouredPalette.muted)
                case .unavailable:
                    Text("Not updated · \(target)").foregroundStyle(HonouredPalette.muted)
                }
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .layoutPriority(1)
    }
}

private struct ShortHealthValue: View {
    let part: HonouredLiveActivityState.HealthPart

    var body: some View {
        if let value = part.value {
            Text(HonouredLiveActivityFormat.shortValueText(value, metric: part.metric, displayUnit: part.displayUnit))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: 52, alignment: .trailing)
                .privacySensitive()
                .accessibilityLabel("\(part.name), \(HonouredLiveActivityFormat.valueText(value, metric: part.metric, displayUnit: part.displayUnit)), \(Int(((HonouredLiveActivityFormat.progress(value: value, target: part.target) ?? 0) * 100).rounded())) percent")
        } else {
            Text("–").foregroundStyle(HonouredPalette.muted)
                .accessibilityLabel("\(part.name), no reading yet")
        }
    }
}

private struct StaleFooter: View {
    let state: HonouredLiveActivityState
    let isStale: Bool

    var body: some View {
        let readings = state.health.compactMap(\.measuredAt)
        let unavailable = state.health.contains { $0.dataStatus == .unavailable }
        if (isStale || unavailable), !state.health.isEmpty, let oldest = readings.min() {
            (Text("Health updated ") + Text(oldest, style: .time))
                .font(.caption)
                .foregroundStyle(HonouredPalette.muted)
        }
    }
}

private struct ResultRow: View {
    let state: HonouredLiveActivityState

    var body: some View {
        if state.status == .completed {
            HStack(alignment: .firstTextBaseline) {
                Text("Honoured")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(HonouredPalette.gold)
                Spacer(minLength: 8)
                if let completedAt = state.completedAt {
                    (Text("Kept at ") + Text(completedAt, style: .time))
                        .font(.caption)
                        .foregroundStyle(HonouredPalette.muted)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("This card has closed.")
                .font(.subheadline)
                .foregroundStyle(HonouredPalette.muted)
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double?
    let reached: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HonouredPalette.track)
                if let fraction {
                    Capsule()
                        .fill(HonouredPalette.gold.opacity(reached ? 1 : 0.85))
                        .frame(width: max(4, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct ProgressRing: View {
    let fraction: Double?
    let symbol: String
    let reached: Bool
    var preservesMetricSymbol = false

    var body: some View {
        ZStack {
            Circle().stroke(HonouredPalette.track, lineWidth: 2.5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(HonouredPalette.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: reached && !preservesMetricSymbol ? "checkmark" : symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(fraction == nil ? HonouredPalette.muted : HonouredPalette.gold)
        }
        .padding(1.5)
        .accessibilityElement()
        .accessibilityLabel(fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? "No reading yet")
    }
}
