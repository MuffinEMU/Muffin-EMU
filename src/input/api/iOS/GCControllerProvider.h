#pragma once

#if BOOST_OS_IOS

#include "input/api/ControllerProvider.h"
#include "input/api/InputAPI.h"

#include <vector>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <algorithm>


// Guarded (rather than relying on this file's own #pragma once) because CemuBridge.h -
// the plain-C header Swift actually imports - carries a byte-for-byte copy of this same
// block so the Swift side never has to see this file's C++ includes. CemuBridge.mm
// includes both headers in one translation unit; whichever is included first wins and
// this guard makes the second inclusion a no-op instead of a duplicate-definition error.
#ifndef GC_BRIDGE_CONTROLLER_TYPES_DEFINED
#define GC_BRIDGE_CONTROLLER_TYPES_DEFINED

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
    uint8 controllerType;
    GCBridgePollStateFn  poll_state;
    GCBridgePollMotionFn poll_motion;
    GCBridgeRumbleFn     rumble;
    GCBridgeReleaseFn    release;
} GCBridgeControllerDesc;

#ifdef __cplusplus
} // extern "C"
#endif

#endif // GC_BRIDGE_CONTROLLER_TYPES_DEFINED

class GCControllerDevice;

class GCControllerProvider : public ControllerProviderBase
{
public:
    inline static InputAPI::Type kAPIType = InputAPI::GCController;

    GCControllerProvider();
    ~GCControllerProvider() override;

    InputAPI::Type api() const override { return InputAPI::GCController; }

    std::vector<std::shared_ptr<ControllerBase>> get_controllers() override;

    void* add_controller(const GCBridgeControllerDesc& desc);
    void  remove_controller(void* handle);
    void configure_controller(void* handle, uint8 type);
    void set_order(void* const* handles, size_t count);
    bool consume_changes();

private:
    mutable std::mutex m_mutex;

    struct Entry {
        std::shared_ptr<GCControllerDevice> device;
    };

    std::unordered_map<void*, Entry> m_controllers;
    std::vector<void*> m_controller_order;
    size_t m_next_player_index = 0;
    bool m_dirty = false;
};

#endif // BOOST_OS_IOS
