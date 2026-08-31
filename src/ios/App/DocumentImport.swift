import UIKit
import UniformTypeIdentifiers

/// Presents the system document picker from UIKit directly, instead of through
/// SwiftUI's `.fileImporter`.
///
/// This exists because the import button kept not working, and the reason is a
/// presentation conflict rather than anything about file types or permissions:
///
///   1. Two `.fileImporter` modifiers on one view do not both work - SwiftUI keeps a
///      single presentation slot per view, so the second button silently does nothing.
///      That was worked around by collapsing them into one modifier whose
///      `allowedContentTypes` was computed from the same state that drives
///      `isPresented`, which is fragile: the modifier has to read the new type list in
///      the same update that flips the presentation on.
///   2. The buttons live inside a `Menu`. Tapping a menu item dismisses the menu, and
///      a modal asked for during that dismissal is dropped by UIKit - the state flips,
///      the body re-renders, and no picker ever appears. That is the "I tap it and
///      nothing happens" case, and no amount of type-list fixing reaches it.
///
/// Driving `UIDocumentPickerViewController` ourselves removes both: each call carries
/// its own fixed type list, and we wait for the menu's dismissal to finish before
/// presenting rather than racing it.
enum DocumentImport {
    /// Opens the picker for `contentTypes` and calls back on the main thread.
    ///
    /// `asCopy: false` on purpose. With `asCopy: true` iOS hands back a URL in a temp
    /// directory that carries no security scope, and `GameManager.importROM` treats a
    /// failed `startAccessingSecurityScopedResource()` as a hard "access denied" - so
    /// copying would break the very import it was meant to simplify. It also cannot
    /// serve a folder pick at all, and a dumped Wii U game IS a folder.
    static func present(
        contentTypes: [UTType],
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        // One turn of the runloop is not enough: the menu is mid-dismissal, not merely
        // scheduled to dismiss, and presenting onto a controller that is going away is
        // how the picker got swallowed. Wait for the dismissal to actually finish.
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

        /// UIDocumentPickerViewController holds its delegate weakly. Without a strong
        /// reference somewhere, this object dies as soon as present() returns and the
        /// picker reports nothing - indistinguishable, from the outside, from the bug
        /// this file exists to fix. Broken as soon as the picker reports back.
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
