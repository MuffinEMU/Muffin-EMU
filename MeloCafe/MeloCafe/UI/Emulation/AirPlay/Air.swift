// Credit https://github.com/heestand-xyz/AirKit

import UIKit
import SwiftUI
import Combine

@MainActor
public final class Air: ObservableObject {
    static let shared = Air()

    @Published public private(set) var connected = false
    @Published private(set) var isPlaying = false
    private var content: AnyView?
    private weak var displayDelegate: ExternalDisplaySceneDelegate?
    private var connectionCallbacks: [(Bool) -> Void] = []

    public static func play(_ view: AnyView) {
        shared.content = view
        shared.isPlaying = true
        shared.presentIfNeeded()
    }

    public static func stop() {
        shared.content = nil
        shared.displayDelegate?.hideContent()
        shared.setConnected(false)
        shared.isPlaying = false
    }

    public static func connection(_ callback: @escaping (Bool) -> Void) {
        shared.connectionCallbacks.append(callback)
    }

    fileprivate func attach(_ delegate: ExternalDisplaySceneDelegate) {
        if displayDelegate !== delegate {
            displayDelegate?.hideContent()
        }
        displayDelegate = delegate
        presentIfNeeded()
    }

    fileprivate func detach(_ delegate: ExternalDisplaySceneDelegate) {
        guard displayDelegate === delegate else { return }
        delegate.hideContent()
        displayDelegate = nil
        setConnected(false)
        // Keep requested content so reconnecting resumes the TV output.
    }

    private func presentIfNeeded() {
        guard let content, let displayDelegate else { return }
        setConnected(true)
        displayDelegate.show(content)
    }

    private func setConnected(_ value: Bool) {
        guard connected != value else { return }
        connected = value
        connectionCallbacks.forEach { $0(value) }
    }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.backgroundColor = .black
        Air.shared.attach(self)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Air.shared.detach(self)
        window = nil
    }

    fileprivate func show(_ content: AnyView) {
        guard let window else { return }
        if let controller = window.rootViewController as? UIHostingController<AnyView> {
            controller.rootView = content
        } else {
            let controller = UIHostingController(rootView: content)
            controller.view.backgroundColor = .black
            window.rootViewController = controller
        }

        window.isHidden = false
    }

    fileprivate func hideContent() {
        window?.isHidden = true
        window?.rootViewController = nil
    }
}
