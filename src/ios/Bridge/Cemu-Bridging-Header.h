// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  Cemu-Bridging-Header.h
//  Exposes the C interface of the Cemu engine bridge to Swift.
//
#import "CemuBridge.h"
// Pure C already, and lives next to CemuBridge.h. This is the in-app launch log the boot
// overlay renders.
#import "IOSLiveLog.h"
// Motion aiming (gyro) settings; also plain C.
#import "IOSMotion.h"
// Pure C as well: the graphic pack screens (scan, list, enable, presets).
#import "IOSGraphicPackBridge.h"
// The device capability snapshot (Common/DeviceCapabilities.h); plain C.
#import "CemuDeviceCaps.h"
