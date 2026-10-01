//
//  AuditBridging-Header.h
//  What the Audit app's Swift sees of the MuffinEMU core: the regular bridge, the live log, the device
//  capabilities and the audit hooks. All plain C. The headers come from the MuffinEMU checkout the
//  core was built from (HEADER_SEARCH_PATHS in project.yml), so the app always matches its core.
//
#import "CemuBridge.h"
#import "IOSLiveLog.h"
#import "CemuDeviceCaps.h"
#import "IOSAuditHooks.h"

// Not declared in any MuffinEMU header: the code-signing status call the Bench app also uses to ask
// whether a JIT enabler is attached (CS_DEBUGGED).
#include <sys/types.h>
#include <stddef.h>
int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);
