// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// Launches the JIT helper app extension as a second process and runs one request.
// The helper has to be a separate process because a process cannot attach a debugger
// to itself. This uses the classic NSExtension host API (private), which launches an
// in-bundle app extension without an App Group or any restricted entitlement, so it
// survives sideload re-signing and costs a free account no extra App ID. The request
// and result travel as data attachments on the extension items, in memory.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MuffinJITLauncher : NSObject

/// Launches the helper identified by `identifier`, hands it `requestData`, and calls
/// `completion` with the helper's `resultData` (or an error). The completion runs on
/// an arbitrary queue.
+ (void)runWithExtensionIdentifier:(NSString *)identifier
                       requestData:(NSData *)requestData
                        completion:(void (^)(NSData *_Nullable resultData,
                                             NSError *_Nullable error))completion
    NS_SWIFT_NAME(run(extensionIdentifier:requestData:completion:));

@end

NS_ASSUME_NONNULL_END
