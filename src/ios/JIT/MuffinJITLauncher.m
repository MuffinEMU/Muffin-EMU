// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// See MuffinJITLauncher.h. This drives the private NSExtension host API: create the
// extension, set a completion block, begin a request carrying the request bytes as an
// item attachment, and read the result bytes back from the returned items. The helper
// extension's principal class receives the request from its NSExtensionContext, runs
// the device-link work, and completes the request with the result.

#import "MuffinJITLauncher.h"

// Private NSExtension host interface. Declared here because there is no public header.
@interface NSExtension : NSObject
+ (nullable instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *requestIdentifier, NSArray *extensionItems))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *requestIdentifier, NSError *error))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *requestIdentifier))block;
- (void)beginExtensionRequestWithInputItems:(nullable NSArray *)inputItems
                                 completion:(void (^)(NSUUID *requestIdentifier))completion;
- (int)pidForRequestIdentifier:(NSUUID *)requestIdentifier;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)requestIdentifier;
@end

// The type identifier the request and result bytes travel under.
static NSString *const kMuffinJITItemType = @"com.muffinemu.jit.payload";

@implementation MuffinJITLauncher

+ (void)runWithExtensionIdentifier:(NSString *)identifier
                       requestData:(NSData *)requestData
                        completion:(void (^)(NSData *_Nullable, NSError *_Nullable))completion {
    Class extClass = NSClassFromString(@"NSExtension");
    if (extClass == nil) {
        completion(nil, [NSError errorWithDomain:@"MuffinJIT" code:-1 userInfo:@{
            NSLocalizedDescriptionKey: @"This iOS build doesn't allow launching the JIT helper."}]);
        return;
    }

    NSError *error = nil;
    NSExtension *ext = [extClass extensionWithIdentifier:identifier error:&error];
    if (ext == nil) {
        completion(nil, error ?: [NSError errorWithDomain:@"MuffinJIT" code:-2 userInfo:@{
            NSLocalizedDescriptionKey: @"The JIT helper isn't installed in this build."}]);
        return;
    }

    // Deliver the result exactly once, whether it arrives, is cancelled, or times out.
    __block BOOL delivered = NO;
    void (^deliver)(NSData *, NSError *) = ^(NSData *data, NSError *err) {
        @synchronized (ext) {
            if (delivered) { return; }
            delivered = YES;
        }
        completion(data, err);
    };

    [ext setRequestCompletionBlock:^(NSUUID *requestIdentifier, NSArray *extensionItems) {
        // The helper returns a single item whose attachment is the result bytes.
        NSItemProvider *provider = [[extensionItems firstObject] attachments].firstObject;
        if (provider == nil) {
            deliver(nil, [NSError errorWithDomain:@"MuffinJIT" code:-3 userInfo:@{
                NSLocalizedDescriptionKey: @"The JIT helper returned nothing."}]);
            return;
        }
        [provider loadItemForTypeIdentifier:kMuffinJITItemType options:nil
                          completionHandler:^(NSData *item, NSError *loadError) {
            if ([item isKindOfClass:[NSData class]]) {
                deliver(item, nil);
            } else {
                deliver(nil, loadError ?: [NSError errorWithDomain:@"MuffinJIT" code:-4 userInfo:@{
                    NSLocalizedDescriptionKey: @"The JIT helper's result couldn't be read."}]);
            }
        }];
    }];

    [ext setRequestCancellationBlock:^(NSUUID *requestIdentifier, NSError *cancelError) {
        deliver(nil, cancelError ?: [NSError errorWithDomain:@"MuffinJIT" code:-5 userInfo:@{
            NSLocalizedDescriptionKey: @"The JIT helper stopped before finishing."}]);
    }];

    // Carry the request bytes as an in-memory attachment — no App Group, no file.
    NSItemProvider *provider = [[NSItemProvider alloc] init];
    [provider registerDataRepresentationForTypeIdentifier:kMuffinJITItemType
                                              visibility:NSItemProviderRepresentationVisibilityAll
                                             loadHandler:^NSProgress *(void (^handler)(NSData *, NSError *)) {
        handler(requestData, nil);
        return nil;
    }];
    NSExtensionItem *item = [[NSExtensionItem alloc] init];
    item.attachments = @[provider];

    [ext beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *requestIdentifier) {
        // The helper is now running in its own process. Its completion arrives through
        // the blocks set above.
        (void)requestIdentifier;
    }];
}

@end
