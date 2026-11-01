// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The JIT helper extension's principal class. The host launches this extension as a
// second process (MuffinJITLauncher), hands it a request as an item attachment, and
// reads the result back the same way. Here we decode the request, run the device-link
// work on a serial queue, and complete the request with the encoded result. This is
// the only place the device-link library is loaded.

import Foundation

private let kMuffinJITItemType = "com.muffinemu.jit.payload"

@objc(MuffinJITHelperPrincipal)
final class MuffinJITHelperPrincipal: NSObject, NSExtensionRequestHandling {
    // One serial queue: the device-link protocol's steps are ordered and must not be
    // split across threads.
    private let queue = DispatchQueue(label: "com.void.muffinemu.jithelper")

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            context.cancelRequest(withError: NSError(domain: "MuffinJIT", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "The JIT helper got no request."]))
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: kMuffinJITItemType) { [weak self] data, error in
            guard let self else { return }
            guard let data else {
                context.cancelRequest(withError: error ?? NSError(domain: "MuffinJIT", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "The JIT helper couldn't read the request."]))
                return
            }
            self.queue.async {
                let resultData = JITHelperCore.runData(data)
                let outProvider = NSItemProvider()
                outProvider.registerDataRepresentation(forTypeIdentifier: kMuffinJITItemType,
                                                       visibility: .all) { completion in
                    completion(resultData, nil)
                    return nil
                }
                let outItem = NSExtensionItem()
                outItem.attachments = [outProvider]
                context.completeRequest(returningItems: [outItem], completionHandler: nil)
            }
        }
    }
}
