import SwiftUI
import UIKit

// Views for the Icon card (V1.2 M2-08). Like the contract card they take plain
// values, not the ActivityKit context, so the unit tests can render them.
//
// Lock Screen, four rows:
//   ∞ Icon                                TUE · 5 OF 17
//   10,000 STEPS · Walking
//   Spring has begun, all life has sprung.
//   [signature]  You've got this. · Due 11:59 pm
// Morning and evening share the layout; only the line of the moment changes.
// The result replaces that line with HONOURED or BROKEN before the card closes.

enum IconPalette {
    static let broken = Color(red: 0.788, green: 0.290, blue: 0.290)
}

struct IconLockScreenView: View {
    let facts: IconCardFacts
    let state: IconLiveActivityState
    /// A morning card turns stale at the evening reminder.
    var isStale: Bool = false
    /// PNG from the App Group signature cache; nil renders no signature.
    var signature: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HonouredBrandMark(width: 28, height: 16)
                Text(IconCopy.title)
                    .font(.system(.headline, design: .serif))
                Spacer(minLength: 8)
                Text(facts.sessionLabel)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(HonouredPalette.gold)
                    .lineLimit(1)
            }
            IconTargetLine(facts: facts)
            if !facts.because.isEmpty {
                Text(facts.because)
                    .font(.system(.footnote, design: .serif).italic())
                    .foregroundStyle(HonouredPalette.ink.opacity(0.85))
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 10) {
                if let signature {
                    // The signature gives way first when the row is tight.
                    Image(uiImage: signature)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: 36, maxWidth: 64, maxHeight: 22, alignment: .leading)
                        .foregroundStyle(HonouredPalette.ink)
                        .layoutPriority(-1)
                        .accessibilityLabel("Your signature")
                }
                IconMomentLine(state: state, isStale: isStale)
                Spacer(minLength: 6)
                // The cut-off is never cut.
                Text(IconCopy.deadlineLabel(facts.deadline))
                    .font(.caption2)
                    .foregroundStyle(HonouredPalette.muted)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
        .padding(14)
        .foregroundStyle(HonouredPalette.ink)
        // Same ceiling as the contract card: four rows stay inside the Lock
        // Screen's height at the largest allowed text size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

private struct IconTargetLine: View {
    let facts: IconCardFacts
    /// The day's Health total so far, shown before the target ("6,240 / 10,000").
    /// The Lock Screen leaves it out: the card shows no progress (client, Sep 28).
    var valueText: String? = nil

    var body: some View {
        // One line whatever the text size: the target shrinks a little before
        // it would wrap, and the activity name gives way first.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let valueText {
                (Text(valueText).foregroundColor(HonouredPalette.gold) + Text(" /").foregroundColor(HonouredPalette.muted))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(3)
                    .privacySensitive()
            }
            Text(facts.targetValue)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(2)
            Text(facts.targetUnit)
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(HonouredPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Text("·").foregroundStyle(HonouredPalette.muted)
            Text(facts.activityName)
                .font(.footnote)
                .foregroundStyle(HonouredPalette.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct IconMomentLine: View {
    let state: IconLiveActivityState
    let isStale: Bool

    var body: some View {
        switch state.result {
        case .honoured?:
            Text(state.line)
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(HonouredPalette.gold)
        case .broken?:
            Text(state.line)
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(IconPalette.broken)
        case nil:
            // The line of the moment is the point of the card: it takes the
            // row's spare width and shrinks a little before it would cut.
            Text(state.displayLine(isStale: isStale))
                .font(.caption.weight(.medium))
                .foregroundStyle(HonouredPalette.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }
}

// MARK: - Dynamic Island: the mark and the day's Health total so far.

struct IconCompactLeadingView: View {
    var body: some View {
        HonouredBrandMark(width: 26, height: 16)
            .frame(width: 30, height: 24)
    }
}

struct IconCompactTrailingView: View {
    let facts: IconCardFacts
    let state: IconLiveActivityState

    var body: some View {
        Group {
            if let value = state.value, let text = IconCopy.shortValue(value, targetUnit: facts.targetUnit) {
                // The current reading, before and after HONOURED (client, Oct 5);
                // gold once the day is kept.
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 64, alignment: .trailing)
                    .foregroundStyle(state.result == .honoured ? HonouredPalette.gold : HonouredPalette.ink)
                    .privacySensitive()
                    .accessibilityLabel("\(facts.activityName), \(text) \(facts.targetUnit.lowercased())")
            } else {
                switch state.result {
                case .honoured?:
                    // No reading on the card yet: the target, which the day reached.
                    Text(facts.targetValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .foregroundStyle(HonouredPalette.gold)
                        .accessibilityLabel("Honoured")
                case .broken?:
                    Image(systemName: "xmark").foregroundStyle(IconPalette.broken)
                        .accessibilityLabel("Broken")
                case nil:
                    Text(facts.targetValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 64, alignment: .trailing)
                }
            }
        }
        .font(.system(.body, design: .rounded).weight(.semibold))
        .foregroundStyle(HonouredPalette.ink)
    }
}

struct IconMinimalView: View {
    var body: some View {
        HonouredBrandMark(width: 22, height: 14)
            .frame(width: 28, height: 24)
    }
}

struct IconExpandedLeadingView: View {
    var body: some View {
        HStack(spacing: 6) {
            HonouredBrandMark(width: 28, height: 16)
            Text(IconCopy.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(HonouredPalette.ink)
        }
        .padding(.leading, 4)
    }
}

struct IconExpandedTrailingView: View {
    let facts: IconCardFacts

    var body: some View {
        Text(facts.sessionLabel)
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(HonouredPalette.gold)
            .lineLimit(1)
            .padding(.trailing, 4)
    }
}

struct IconExpandedBottomView: View {
    let facts: IconCardFacts
    let state: IconLiveActivityState
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IconTargetLine(
                facts: facts,
                valueText: state.value.flatMap { IconCopy.shortValue($0, targetUnit: facts.targetUnit) }
            )
            HStack {
                IconMomentLine(state: state, isStale: isStale)
                Spacer(minLength: 6)
                Text(IconCopy.deadlineLabel(facts.deadline))
                    .font(.caption2)
                    .foregroundStyle(HonouredPalette.muted)
            }
        }
        .foregroundStyle(HonouredPalette.ink)
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
