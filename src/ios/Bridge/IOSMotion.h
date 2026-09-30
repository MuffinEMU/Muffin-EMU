//
//  IOSMotion.h
//  Motion for the emulated GamePad: the device's own gyroscope and accelerometer (or a
//  controller's), turned into the values the core's motion handler expects. Plain C, so
//  Swift can import it through the bridging header next to CemuBridge.h.
//
//  Games that aim with the GamePad's gyro (Splatoon, Zelda's first-person bows, ...) read
//  these values through VPADRead. Nothing here is per title.
//
#ifndef IOS_MOTION_H
#define IOS_MOTION_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Where the GamePad's motion comes from.
typedef enum {
    /// This iPad or iPhone. Held like the GamePad, tilting and turning the device aims.
    CEMU_BRIDGE_MOTION_SOURCE_DEVICE     = 0,
    /// The first connected controller that has motion sensors (DualShock 4, DualSense,
    /// Switch Pro Controller, ...). Falls back to the device when there is none.
    CEMU_BRIDGE_MOTION_SOURCE_CONTROLLER = 1,
} CemuBridgeMotionSource;

/// What is feeding the GamePad's motion right now, for the Settings readout.
typedef enum {
    CEMU_BRIDGE_MOTION_STATUS_OFF         = 0, // switched off: the game sees a GamePad lying still
    CEMU_BRIDGE_MOTION_STATUS_DEVICE      = 1, // this device's sensors
    CEMU_BRIDGE_MOTION_STATUS_CONTROLLER  = 2, // a controller's sensors
    CEMU_BRIDGE_MOTION_STATUS_UNAVAILABLE = 3, // on, but this device has no motion sensors
} CemuBridgeMotionStatus;

/// Motion aiming on or off. Off is what "stick only" means: the game is handed a GamePad
/// that never moves. A game with its own in-game motion option (Splatoon has one) should
/// have that switched off as well, otherwise it still expects the GamePad to move.
/// Takes effect at once; safe to call from any thread, before or during a title.
void cemu_bridge_set_motion_enabled(bool enabled);

/// Scales how fast the GamePad turns for a given movement of the device. 1.0 is true to
/// life, 2.0 turns twice as far. Clamped to 0.25 ... 4.0.
void cemu_bridge_set_motion_sensitivity(float sensitivity);

/// One of CemuBridgeMotionSource.
void cemu_bridge_set_motion_source(int source);

/// Forgets where the GamePad has been pointing and takes the current pose as "straight
/// ahead", like pressing the recentre button in a game that has one. Use it when aim has
/// crept off after long play or after turning in your seat.
void cemu_bridge_motion_recenter(void);

/// One of CemuBridgeMotionStatus.
int cemu_bridge_motion_status(void);

/// True while a connected controller has motion sensors (whether or not it is in use).
bool cemu_bridge_motion_controller_available(void);

// --- used by CemuBridge.mm, not by Swift ---

typedef struct {
    /// In the core's motion-handler convention (src/input/motion/MotionHandler.h): gravity
    /// in g, angular rate in rad/s, both already turned into the GamePad's axes.
    float accelerometer[3];
    float gyroscope[3];
    /// Seconds on a monotonic clock. Only moves forward when there is new data.
    double timestamp;
    /// Changes every time cemu_bridge_motion_recenter() is called.
    uint32_t recenterCount;
} IOSMotionSample;

/// Registers for controller and orientation changes. Idempotent, cheap.
void IOSMotion_Start(void);

/// The latest sample for the emulated GamePad. Called from the title's own thread on every
/// VPADRead, so it must not block. Wakes the sensors the first time it is called and lets
/// them sleep again a few seconds after the last call, so nothing runs while no title does.
void IOSMotion_Poll(IOSMotionSample* out);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // IOS_MOTION_H
