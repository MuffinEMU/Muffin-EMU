//
//  Cemu-Bridging-Header.h
//  Exposes the C interface of the Cemu engine bridge to Swift.
//
#import "CemuBridge.h"
// Pure C already, and reachable via HEADER_SEARCH_PATHS' $(SRCROOT)/.. - no shim in
// CemuBridge.h. This is the in-app launch log the boot overlay renders.
#import "Cemu/Logging/IOSLiveLog.h"
