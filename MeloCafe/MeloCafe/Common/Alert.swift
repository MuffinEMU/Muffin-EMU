//
//  Alert.swift
//  MeloCafe (definitely not yoinked from MeloNX :3)
//
//  Created by Stossy11 on 30/4/2026.
//

import Foundation
import UIKit
import SwiftUI

class AppAlerts {
    static func topViewController() -> UIViewController? {
        let rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController ?? UIApplication.shared.windows.first?.rootViewController
        
        guard let rootViewController else {
            return nil
        }
        
        return topMost(of: rootViewController)
    }
    
    private static func topMost(of viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topMost(of: presented)
        }
        
        if let navigationController = viewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topMost(of: visibleViewController)
        }
        
        if let tabController = viewController as? UITabBarController,
           let selectedViewController = tabController.selectedViewController {
            return topMost(of: selectedViewController)
        }
        
        return viewController
    }
    
    static func showAlert(_ viewController: UIViewController? = nil,
                          title: String?,
                          message: String?,
                          actions: [(title: String, style: UIAlertAction.Style, handler: (() -> Void)?)]) {
        
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        for action in actions {
            let uiAction = UIAlertAction(title: action.title, style: action.style) { _ in
                action.handler?()
            }
            alert.addAction(uiAction)
        }
        
        if Thread.isMainThread {
            let coolVC = viewController ?? topViewController()
            coolVC?.present(alert, animated: true, completion: nil)
        } else {
            DispatchQueue.main.async {
                let coolVC = viewController ?? topViewController()
                coolVC?.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    @discardableResult
    static func showSyncAlert(
        title: String?,
        message: String?,
        actions: [String] = ["OK"],
        hasCancel: Bool = true,
        alertHandler: @escaping (String) -> Void = { _ in }
    ) -> UIAlertController? {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        for actionTitle in actions {
            alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
                alertHandler(actionTitle)
            })
        }
        
        if hasCancel {
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                alertHandler("Cancel")
            })
        }
        
        Task { @MainActor in
            topViewController()?.present(alert, animated: true)
        }
        
        return alert
    }
    
    @MainActor
    static func showTextFieldAlert(
        title: String?,
        message: String?,
        default defaultText: String?,
        action: String = "OK",
    ) async -> String? {
        await withCheckedContinuation { continuation in
            guard let presenter = topViewController() else {
                continuation.resume(returning: "NoPresenter")
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField()
            
            alert.textFields![0].text = defaultText
            
            alert.addAction(UIAlertAction(title: action, style: .default) { _ in
                let answer = alert.textFields![0]
                
                continuation.resume(returning: answer.text)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: defaultText)
            })
            
            presenter.present(alert, animated: true)
        }
    }
    
    @MainActor
    static func showAlert(
        title: String?,
        message: String?,
        actions: [String] = ["OK"],
        hasCancel: Bool = true
    ) async -> String {
        
        await withCheckedContinuation { continuation in
            guard let presenter = topViewController() else {
                continuation.resume(returning: "NoPresenter")
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            for actionTitle in actions {
                alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
                    continuation.resume(returning: actionTitle)
                })
            }
            
            if hasCancel {
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: "Cancel")
                })
            }
            
            presenter.present(alert, animated: true)
        }
    }
}
