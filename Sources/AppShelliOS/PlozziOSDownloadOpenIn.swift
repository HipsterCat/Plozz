#if os(iOS)
import CoreNetworking
import MediaDownloads
import SwiftUI
import UIKit

struct DownloadOpenInFile: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct DownloadOpenInModifier: ViewModifier {
    @Binding var record: DownloadedMediaRecord?
    let model: PlozziOSDownloadsModel
    let appModel: PlozziOSAppModel
    @State private var file: DownloadOpenInFile?
    @State private var failure: LocalizedStringResource?

    private var isAuthorized: Bool {
        appModel.isActiveProfileAuthorized && model.profileID == appModel.profiles.activeProfileID
    }

    func body(content: Content) -> some View {
        content
            .background {
                DownloadOpenInPresenter(file: isAuthorized ? file : nil) { id, unavailable in
                    guard file?.id == id, isAuthorized else { return }
                    file = nil
                    record = nil
                    if unavailable {
                        PlozzLog.app.error("No compatible app accepted the downloaded file.")
                        failure = "No compatible apps are available for this download."
                    }
                }
            }
            .task(id: record) {
                file = nil
                guard let record, isAuthorized else { return }
                do {
                    let url = try await model.fileURLForExport(record)
                    try Task.checkCancellation()
                    guard isAuthorized else { return }
                    file = DownloadOpenInFile(url: url, title: record.snapshot.title)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, isAuthorized else { return }
                    PlozzLog.app.error("Unable to open the downloaded file in another app.")
                    self.record = nil
                    failure = "This download is no longer available. Try downloading it again."
                }
            }
            .onChange(of: isAuthorized) { _, authorized in
                if !authorized {
                    file = nil
                    record = nil
                    failure = nil
                }
            }
            .onDisappear {
                file = nil
                record = nil
            }
            .alert("Open in…", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )) {
                Button("OK") { failure = nil }
            } message: {
                if let failure { Text(failure) }
            }
    }
}

struct DownloadOpenInPresenter: UIViewControllerRepresentable {
    let file: DownloadOpenInFile?
    let completion: (UUID, Bool) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configure(file: file, completion: completion)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.cancel()
    }

    final class Controller: UIViewController, UIDocumentInteractionControllerDelegate {
        private var file: DownloadOpenInFile?
        private var completion: ((UUID, Bool) -> Void)?
        private var document: UIDocumentInteractionController?
        private var isSending = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfReady()
        }

        func configure(file: DownloadOpenInFile?, completion: @escaping (UUID, Bool) -> Void) {
            self.completion = completion
            guard self.file?.id != file?.id else { return }
            cancel()
            self.file = file
            presentIfReady()
        }

        private func presentIfReady() {
            guard document == nil, let file, viewIfLoaded?.window != nil else { return }
            let document = UIDocumentInteractionController(url: file.url)
            document.name = file.title
            document.delegate = self
            self.document = document
            // UIKit grants the receiving app access; a file URL embedded in an
            // external player's custom URL scheme would not grant that access.
            if !document.presentOpenInMenu(
                from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                in: view, animated: true
            ) {
                finish(unavailable: true)
            }
        }

        func cancel() {
            document?.delegate = nil
            document?.dismissMenu(animated: false)
            document = nil
            file = nil
            isSending = false
        }

        private func finish(unavailable: Bool = false) {
            guard let file, let document else { return }
            document.delegate = nil
            isSending = false
            let completion = completion
            Task { @MainActor in completion?(file.id, unavailable) }
        }

        func documentInteractionController(
            _ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?
        ) {
            guard document === controller else { return }
            isSending = true
        }

        func documentInteractionController(
            _ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?
        ) {
            guard document === controller else { return }
            finish()
        }

        func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
            guard document === controller else { return }
            if !isSending { finish() }
        }
    }
}
#endif
