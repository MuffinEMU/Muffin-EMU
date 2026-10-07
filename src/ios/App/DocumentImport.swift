// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import UIKit
import UniformTypeIdentifiers

/// Presents the document picker from UIKit so it can wait for a dismissing Menu;
/// `.fileImporter` inside a Menu is dropped by SwiftUI.
enum DocumentImport {
    /// Opens the picker for `contentTypes` and calls back on the main thread.
    ///
    /// `asCopy` is false so the URL keeps its security scope and folders can be picked.
    static func present(
        contentTypes: [UTType],
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        // Wait for the menu to finish dismissing; presenting during dismissal is dropped.
        waitForStablePresenter(attemptsLeft: 20) { presenter in
            guard let presenter else {
                completion(.failure(PresentationError.noPresenter))
                return
            }

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: contentTypes,
                asCopy: false
            )
            picker.allowsMultipleSelection = false
            // The library accepts .rpx/.wux/.wud/.wua, none of which iOS knows by name.
            // Showing extensions is the only way to tell two dumps of the same game
            // apart in the picker.
            picker.shouldShowFileExtensions = true
            picker.modalPresentationStyle = .formSheet

            let delegate = Delegate(completion: completion)
            picker.delegate = delegate
            // UIDocumentPickerViewController holds its delegate weakly, so without this
            // the delegate deallocates the moment this function returns and the picker
            // reports nothing at all - which looks identical to the bug being fixed.
            delegate.retainSelf()

            presenter.present(picker, animated: true)
        }
    }

    /// The other direction: hand a file or folder we already have to wherever the user
    /// wants to put it.
    ///
    /// Same presenter-stability dance as present() above, for the same reason - this is
    /// also reached from a dismissing sheet, and presenting onto a controller that is
    /// going away swallows the picker without a word.
    ///
    /// `asCopy: true` because the thing being exported lives inside the app's own
    /// storage and must stay there. Without it the picker MOVES the directory out, which
    /// for a save folder means exporting it deletes it.
    static func presentExport(
        _ urls: [URL],
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        waitForStablePresenter(attemptsLeft: 20) { presenter in
            guard let presenter else {
                completion(.failure(PresentationError.noPresenter))
                return
            }

            let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
            picker.shouldShowFileExtensions = true
            picker.modalPresentationStyle = .formSheet

            let delegate = Delegate(completion: completion)
            picker.delegate = delegate
            delegate.retainSelf()

            presenter.present(picker, animated: true)
        }
    }

    enum PresentationError: LocalizedError {
        case noPresenter

        var errorDescription: String? {
            switch self {
            case .noPresenter:
                return "Couldn't open the file picker - the app had no visible window to open it from."
            }
        }
    }

    /// Walks to the top-most view controller, but only once nothing on the way there is
    /// in the middle of appearing or disappearing. Retries roughly every 50 ms and gives
    /// up after about a second rather than waiting forever on a stuck transition.
    private static func waitForStablePresenter(
        attemptsLeft: Int,
        _ body: @escaping (UIViewController?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let top = topViewController() else {
                body(nil)
                return
            }

            if (top.isBeingDismissed || top.isBeingPresented) && attemptsLeft > 0 {
                waitForStablePresenter(attemptsLeft: attemptsLeft - 1, body)
                return
            }

            body(top)
        }
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<[URL], Error>) -> Void
        private var selfReference: Delegate?

        init(completion: @escaping (Result<[URL], Error>) -> Void) {
            self.completion = completion
        }

        /// The picker holds its delegate weakly, so the delegate retains itself until the picker reports back.
        func retainSelf() {
            selfReference = self
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Not an error - the user changed their mind, and an alert here would be
            // the app arguing with them.
            finish(.success([]))
        }

        private func finish(_ result: Result<[URL], Error>) {
            completion(result)
            selfReference = nil
        }
    }
}
