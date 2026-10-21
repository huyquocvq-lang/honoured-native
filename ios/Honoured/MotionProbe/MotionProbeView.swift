import SwiftUI
import UIKit
import UserNotifications

/// The hidden probe screen, opened with `honoured://motion-probe` on Debug and
/// TestFlight builds. Test instructions: docs/phase3/m1-probe-guide.md.
struct MotionProbeView: View {
    @StateObject private var model = MotionProbeScreenModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                Section {
                    Toggle("Record app runs", isOn: Binding(
                        get: { model.snapshot.enabled },
                        set: { model.setEnabled($0) }
                    ))
                } footer: {
                    Text("While on, every launch, HealthKit wake, background refresh and unlock reads Core Motion and HealthKit and writes a line to the log on this iPhone.")
                }
                if model.snapshot.enabled {
                    sessionSection
                    resultsSection
                    eventsSection
                }
            }
            .navigationTitle("Motion probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        // Live Core Motion updates only while the screen is on screen.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            model.disappear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.appear()
        }
        .sheet(item: $model.export) { export in
            ActivityView(items: [export.url])
        }
        .confirmationDialog("Delete the probe log, reports and session?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.clear() }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            row("Build", model.build)
            row("Motion & Fitness", model.motionStatus)
            row("HealthKit", model.healthStatus)
            row("Notifications", model.notificationStatus)
            if model.motionStatus.hasPrefix("not_determined") {
                Button("Allow Motion & Fitness") { model.askMotion() }
            }
            if model.canAskHealth {
                Button("Allow Health steps, distance and energy") { model.askHealth() }
            }
            if model.notificationStatus == "not_determined" {
                Button("Allow notifications") { model.askNotifications() }
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section {
            if let session = model.snapshot.session, session.isRunning {
                row("Started", Self.clock(session.startedAt))
                row("Target", "\(Int(session.targetSteps)) steps")
                row("Core Motion", model.snapshot.liveSteps.map { "\(Int($0)) steps" } ?? "—")
                row("HealthKit", model.snapshot.healthSteps.map { "\(Int($0)) steps" } ?? "—")
                ForEach(session.detected.keys.sorted(), id: \.self) { source in
                    row("Noticed (\(Self.name(source)))", session.detected[source].map(Self.clock) ?? "—")
                }
                Button("Stop session", role: .destructive) { model.stopSession() }
            } else {
                Stepper("Target: \(Int(model.targetSteps)) steps", value: $model.targetSteps, in: 100...20_000, step: 100)
                Button("Start session") { model.startSession() }
            }
        } header: {
            Text("Session")
        } footer: {
            Text("Counts start at zero for both sources when the session starts. Walk until the target, then follow the test case in the guide.")
        }
    }

    private var resultsSection: some View {
        Section("Results") {
            Button(model.rebuilding ? "Rebuilding…" : "Rebuild crossing times") { model.rebuild() }
                .disabled(model.rebuilding || model.snapshot.session == nil)
            Button("Rebuild all sessions") { model.rebuildAll() }
                .disabled(model.rebuilding)
            if let report = model.snapshot.lastReport {
                Text(report)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button("Export log") { model.exportLog() }
            Button("Delete log", role: .destructive) { confirmClear = true }
        }
    }

    private var eventsSection: some View {
        Section("Recent events") {
            ForEach(Array(model.snapshot.recent.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.clock(event.at))  \(event.event)\(event.source.map { " · \(Self.name($0))" } ?? "")")
                        .font(.system(.footnote, design: .monospaced))
                    let detail = Self.detail(event)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func name(_ source: String) -> String {
        source == MotionProbe.coreMotion ? "Core Motion" : source == MotionProbe.healthKit ? "HealthKit" : source
    }

    private static func detail(_ event: MotionProbeEvent) -> String {
        var parts: [String] = []
        if let reason = event.reason { parts.append(reason) }
        if event.certainty != .recorded { parts.append(event.certainty.rawValue) }
        for (key, value) in (event.numbers ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("\(key)=\(value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value))")
        }
        for (key, value) in (event.notes ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("\(key)=\(value)")
        }
        return parts.joined(separator: " ")
    }
}

@MainActor
final class MotionProbeScreenModel: ObservableObject {
    struct Export: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    @Published var snapshot = MotionProbe.Snapshot(enabled: MotionProbe.isEnabled, session: nil, liveSteps: nil,
                                                   healthSteps: nil, recent: [], lastReport: nil)
    @Published var targetSteps: Double = 1_000
    @Published var motionStatus = MotionProbePedometer.authorization
    @Published var healthStatus = "…"
    @Published var notificationStatus = "…"
    @Published var canAskHealth = false
    @Published var rebuilding = false
    @Published var export: Export?
    @Published var build = "…"

    private var loop: Task<Void, Never>?

    func appear() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.refresh(poll: tick % 15 == 0)
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        Task { await MotionProbe.shared.startLiveUpdates() }
    }

    func disappear() {
        loop?.cancel()
        loop = nil
        Task { await MotionProbe.shared.stopLiveUpdates() }
    }

    private func refresh(poll: Bool) async {
        if poll {
            await MotionProbe.shared.pollFromScreen()
            await refreshPermissions()
        }
        snapshot = await MotionProbe.shared.snapshot()
    }

    private func refreshPermissions() async {
        build = await MotionProbeAccess.buildKind()
        motionStatus = MotionProbePedometer.isAvailable
            ? MotionProbePedometer.authorization
            : "\(MotionProbePedometer.authorization), no pedometer"
        let health = await HealthKitService.shared.permissionStatusPayload(for: [.steps, .distanceWalkingRunning, .activeEnergy])
        let available = health["available"] as? Bool ?? false
        let perMetric = health["perMetric"] as? [String: String] ?? [:]
        canAskHealth = available && perMetric.values.contains("notDetermined")
        healthStatus = available ? (canAskHealth ? "not asked yet" : "asked (iOS hides the answer)") : "unavailable"
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationStatus = "authorized"
        case .denied: notificationStatus = "denied"
        case .notDetermined: notificationStatus = "not_determined"
        @unknown default: notificationStatus = "unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        Task {
            await MotionProbe.shared.setEnabled(enabled)
            if enabled { await MotionProbe.shared.recordRun(reason: .probeScreen) }
            await refresh(poll: true)
        }
    }

    func askMotion() {
        Task {
            _ = await MotionProbePedometer.read(from: Date().addingTimeInterval(-60), to: Date())
            await refresh(poll: true)
        }
    }

    func askHealth() {
        Task {
            try? await HealthKitService.shared.requestAuthorization(for: [.steps, .distanceWalkingRunning, .activeEnergy])
            await refresh(poll: true)
        }
    }

    func askNotifications() {
        Task {
            _ = await NotificationCoordinator.shared.requestPermissionIfNeeded()
            await refresh(poll: true)
        }
    }

    func startSession() {
        Task {
            await MotionProbe.shared.startSession(targetSteps: targetSteps)
            await MotionProbe.shared.startLiveUpdates()
            await refresh(poll: false)
        }
    }

    func stopSession() {
        Task {
            await MotionProbe.shared.stopSession()
            await refresh(poll: false)
        }
    }

    func rebuild() {
        rebuilding = true
        Task {
            _ = await MotionProbe.shared.rebuildReport()
            rebuilding = false
            await refresh(poll: false)
        }
    }

    func rebuildAll() {
        rebuilding = true
        Task {
            _ = await MotionProbe.shared.rebuildAllSessions()
            rebuilding = false
            await refresh(poll: false)
        }
    }

    func exportLog() {
        Task {
            if let url = try? await MotionProbe.shared.exportArchive() {
                export = Export(url: url)
            }
        }
    }

    func clear() {
        Task {
            await MotionProbe.shared.clearLog()
            await refresh(poll: false)
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
