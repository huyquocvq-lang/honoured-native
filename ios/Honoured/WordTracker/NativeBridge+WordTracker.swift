import Foundation
import UniformTypeIdentifiers
import UIKit

extension NativeBridge {
    static let wordTrackerMessageTypes: Set<String> = [
        "SELECT_WORD_SOURCE", "GET_WORD_SOURCE_STATE", "READ_WORD_SOURCE", "REMOVE_WORD_SOURCE",
        "CLEAR_WORD_SOURCES", "SET_WORD_REMINDERS",
    ]

    /// Reminder lists replace each other, so they are applied in arrival order.
    static let wordReminderQueue = SerialAsyncQueue()

    func wordTrackerCapability() -> [String: Any] {
        [
            "protocolVersion": 1,
            "supported": trustedWebOrigin != nil,
            "sourceKinds": WordSourceKind.allCases.map(\.rawValue),
        ]
    }

    @MainActor
    func handleWordTracker(type: String, payload: [String: Any], requestId: String?) {
        let generation = googleAuth.documentGeneration
        let respond: (String, [String: Any]) -> Void = { [weak self] replyType, body in
            DispatchQueue.main.async {
                guard let self, self.googleAuth.documentGeneration == generation else { return }
                var body = body
                if let requestId { body["requestId"] = requestId }
                self.dispatchNow(type: replyType, payload: body, generation: generation)
            }
        }
        guard let requestId, !requestId.isEmpty,
              let userId = boundAuthUserId, !userId.isEmpty else {
            respond("WORD_SOURCE_ERROR", ["code": "invalid_payload", "recoverable": false])
            return
        }
        if type == "CLEAR_WORD_SOURCES" {
            // Sent after the account is deleted, before its session is cleared.
            WordSourceBookmarkStore.removeAll(for: userId)
            respond("WORD_SOURCES_CLEARED", [:])
            return
        }
        if type == "SET_WORD_REMINDERS" {
            // The whole list for the signed-in account; sign-out and an
            // account switch already cancel every local notification.
            guard let reminders = WordReminder.parseList(payload["reminders"]) else {
                respond("WORD_SOURCE_ERROR", ["code": "invalid_payload", "recoverable": false])
                return
            }
            Self.wordReminderQueue.enqueue {
                let result = await NotificationCoordinator.shared.replaceWordReminders(reminders)
                respond("WORD_REMINDERS_SET", ["scheduled": result.scheduled, "authorized": result.authorized])
            }
            return
        }
        guard let contractId = payload["contractId"] as? String,
              !contractId.isEmpty, contractId.count <= 256 else {
            respond("WORD_SOURCE_ERROR", ["code": "invalid_payload", "recoverable": false])
            return
        }

        switch type {
        case "SELECT_WORD_SOURCE":
            // Reconnecting a signed Icon keeps the source id the server locked.
            var keptSourceId: String?
            if let value = payload["sourceId"] {
                guard let id = value as? String, WordSourceSupport.isValidSourceId(id) else {
                    respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "invalid_payload", "recoverable": false])
                    return
                }
                keptSourceId = id
            }
            guard wordSourceSelection == nil else {
                respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "in_progress", "recoverable": true])
                return
            }
            guard let presenter = wordPickerPresenter() else {
                respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "provider_unavailable", "recoverable": true])
                return
            }
            let selection = WordSourceSelection { [weak self] result in
                guard let self else { return }
                self.wordSourceSelection = nil
                switch result {
                case .cancelled:
                    respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "cancelled", "recoverable": true])
                case .selected(let url):
                    self.acceptWordSource(
                        url, userId: userId, contractId: contractId, sourceId: keptSourceId, respond: respond
                    )
                }
            }
            wordSourceSelection = selection
            let picker = selection.makePicker()
            presenter.present(picker, animated: true)

        case "GET_WORD_SOURCE_STATE":
            Task.detached(priority: .userInitiated) {
                do {
                    guard let source = try WordSourceBookmarkStore.load(userId: userId, contractId: contractId) else {
                        respond("WORD_SOURCE_STATE", ["contractId": contractId, "status": "none"])
                        return
                    }
                    // A bookmark that no longer resolves needs the person to
                    // choose the same source again; nothing is read here.
                    let resolvable = (try? WordSourceBookmarkStore.resolve(source)) != nil
                    respond("WORD_SOURCE_STATE", [
                        "contractId": contractId, "status": resolvable ? "selected" : "needs_reconnect",
                        "sourceId": source.sourceId, "sourceKind": source.kind.rawValue,
                    ])
                } catch {
                    respond("WORD_SOURCE_ERROR", [
                        "contractId": contractId, "code": WordSourceSupport.safeError(error).rawValue, "recoverable": true,
                    ])
                }
            }

        case "READ_WORD_SOURCE":
            guard let expectedSourceId = payload["sourceId"] as? String,
                  WordSourceSupport.isValidSourceId(expectedSourceId) else {
                respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "invalid_payload", "recoverable": false])
                return
            }
            // One read per source at a time; a large project can take a while.
            let readKey = userId + "|" + contractId
            guard !wordReadsInFlight.contains(readKey) else {
                respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "in_progress", "recoverable": true])
                return
            }
            wordReadsInFlight.insert(readKey)
            Task.detached(priority: .userInitiated) { [weak self] in
                let (replyType, body) = Self.readWordSource(
                    userId: userId, contractId: contractId, expectedSourceId: expectedSourceId
                )
                await MainActor.run { _ = self?.wordReadsInFlight.remove(readKey) }
                respond(replyType, body)
            }

        case "REMOVE_WORD_SOURCE":
            guard let expectedSourceId = payload["sourceId"] as? String,
                  let source = try? WordSourceBookmarkStore.load(userId: userId, contractId: contractId),
                  source.sourceId == expectedSourceId else {
                respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "source_mismatch", "recoverable": true])
                return
            }
            WordSourceBookmarkStore.remove(userId: userId, contractId: contractId)
            respond("WORD_SOURCE_STATE", ["contractId": contractId, "status": "none"])

        default:
            respond("WORD_SOURCE_ERROR", ["contractId": contractId, "code": "unsupported", "recoverable": false])
        }
    }

    /// Reads the count off the main thread. Only the count, the source's
    /// opaque id and kind, a time and a random revision leave this function.
    nonisolated private static func readWordSource(
        userId: String, contractId: String, expectedSourceId: String
    ) -> (String, [String: Any]) {
        do {
            guard let source = try WordSourceBookmarkStore.load(userId: userId, contractId: contractId) else {
                throw WordSourceError.missing
            }
            guard source.sourceId == expectedSourceId else { throw WordSourceError.sourceMismatch }
            let (url, isStale) = try WordSourceBookmarkStore.resolve(source)
            guard url.startAccessingSecurityScopedResource() else { throw WordSourceError.permissionDenied }
            defer { url.stopAccessingSecurityScopedResource() }
            // A moved or renamed file is still the same source. If the new
            // bookmark cannot be written, this read still goes ahead.
            if isStale { try? WordSourceBookmarkStore.refresh(source, url: url) }
            let count = try WordDocumentReader.count(url: url, kind: source.kind)
            return ("WORD_READING_UPDATED", [
                "contractId": contractId, "sourceId": source.sourceId,
                "sourceKind": source.kind.rawValue, "count": count,
                "readAt": ISO8601DateFormatter().string(from: Date()),
                "revision": UUID().uuidString.lowercased(),
            ])
        } catch {
            return ("WORD_SOURCE_ERROR", [
                "contractId": contractId, "code": WordSourceSupport.safeError(error).rawValue, "recoverable": true,
            ])
        }
    }

    @MainActor
    private func acceptWordSource(
        _ url: URL,
        userId: String,
        contractId: String,
        sourceId: String?,
        respond: @escaping (String, [String: Any]) -> Void
    ) {
        // A picked URL is security-scoped: open access before reading its
        // attributes and creating the bookmark.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard let kind = WordSourceSupport.kind(
                fileExtension: url.pathExtension,
                isDirectory: values.isDirectory == true
            ) else { throw WordSourceError.unsupportedType }
            let source = try WordSourceBookmarkStore.save(
                url: url, userId: userId, contractId: contractId, kind: kind, sourceId: sourceId
            )
            respond("WORD_SOURCE_SELECTED", [
                "contractId": contractId, "sourceId": source.sourceId, "sourceKind": source.kind.rawValue,
            ])
        } catch {
            respond("WORD_SOURCE_ERROR", [
                "contractId": contractId, "code": WordSourceSupport.safeError(error).rawValue, "recoverable": true,
            ])
        }
    }

    @MainActor
    private func wordPickerPresenter() -> UIViewController? {
        var current = webView?.window?.rootViewController
        while let presented = current?.presentedViewController { current = presented }
        return current
    }
}

enum WordSourceSelectionResult {
    case selected(URL)
    case cancelled
}

@MainActor
final class WordSourceSelection: NSObject, UIDocumentPickerDelegate {
    private var completion: ((WordSourceSelectionResult) -> Void)?

    init(completion: @escaping (WordSourceSelectionResult) -> Void) {
        self.completion = completion
    }

    func makePicker() -> UIDocumentPickerViewController {
        var types = ["org.openxmlformats.wordprocessingml.document", "public.plain-text", "public.rtf", "com.apple.rtfd"]
            .compactMap(UTType.init)
        // A .scriv project is a folder. The type declared for its extension
        // (Scrivener's own when it is installed, otherwise the one this app
        // imports in Info.plist) lets the picker offer it as one document.
        if let scrivener = UTType(filenameExtension: "scriv", conformingTo: .package) {
            types.append(scrivener)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        return picker
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first.map(WordSourceSelectionResult.selected) ?? .cancelled)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.cancelled) }

    private func finish(_ result: WordSourceSelectionResult) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}
