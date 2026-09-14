//
//  Controller.h
//  MeloCafe
//
//  Created by Stossy11 on 9/3/2026.
//

#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float x, y;
} GCBridgeVec2;

typedef struct {
    float x, y, z;
} GCBridgeVec3;

typedef struct {
    float w, x, y, z;
} GCBridgeQuat;

typedef struct {
    uint32_t buttons;
    GCBridgeVec2 leftStick;
    GCBridgeVec2 rightStick;
    float leftTrigger;
    float rightTrigger;
} GCBridgeControllerState;

typedef struct {
    GCBridgeVec3 accelerometer;
    GCBridgeVec3 gyroscope;
    GCBridgeVec3 orientation;
    GCBridgeQuat quaternion;
    // Monotonic sample time in seconds; zero means no sample received yet.
    double timestamp;
} GCBridgeMotionState;

typedef GCBridgeControllerState (*GCBridgePollStateFn)(void* context);

typedef GCBridgeMotionState     (*GCBridgePollMotionFn)(void* context);

typedef void (*GCBridgeRumbleFn)(void* context, bool start);

typedef void (*GCBridgeReleaseFn)(void* context);

typedef struct {
    void* context;
    const char* display_name;
    uint8_t controllerType;
    GCBridgePollStateFn  poll_state;
    GCBridgePollMotionFn poll_motion;
    GCBridgeRumbleFn     rumble;
    GCBridgeReleaseFn    release;
} GCBridgeControllerDesc;

void* GCControllerBridge_add(const GCBridgeControllerDesc* desc);

void  GCControllerBridge_remove(void* handle);

void GCControllerBridge_configure(void* handle, uint8_t type);
void GCControllerBridge_setOrder(void* const* handles, size_t count);
void GCControllerBridge_notifyChanged(void);

#ifdef __cplusplus
} // extern "C"
#endif
