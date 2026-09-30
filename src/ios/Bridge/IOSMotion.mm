//
//  IOSMotion.mm
//  Motion for the emulated GamePad. See IOSMotion.h.
//
//  The GamePad's frame, as the core's motion handler and the real console see it (the same one
//  SDL uses for a controller lying face up):
//    X  to the right of the screen
//    Y  out of the screen, toward the ceiling when the pad lies flat
//    Z  toward the bottom edge of the screen, toward the player when the pad lies flat
//  A flat pad reads gravity along Y, and the handler's default pose is exactly that.
//
//  Devices report in their own frame (CoreMotion: X right, Y toward the top of the device in
//  portrait, Z out of the screen, gravity read as the vector toward the ground). Two steps
//  connect them:
//    1. Turn the device frame into a SCREEN frame (right, up, out) for the orientation the
//       interface is in, so the same tilt means the same thing in both landscape orientations.
//    2. Turn the screen frame into the handler's convention - the same arithmetic the core's
//       SDL controller path ends up with (SDLControllerProvider.cpp): reading (x,y,z) in the
//       GamePad frame becomes acc = (x, -y, -z) and gyro = (x, -y, -z).
//  Put together, a screen-frame reading (sx, sy, sz) becomes (sx, -sz, sy) for both.
//
//  Compiled with ARC and without the core's precompiled header: nothing here needs the core.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>

#include "IOSMotion.h"
#include "CemuBridge.h"

namespace {

constexpr double kUpdateInterval = 1.0 / 100.0; // the fastest CoreMotion delivers device motion
constexpr double kIdleSeconds = 3.0;            // no VPADRead for this long: stop the sensors
constexpr float kMinSensitivity = 0.25f;
constexpr float kMaxSensitivity = 4.0f;

std::atomic<bool> g_enabled{true};
std::atomic<float> g_sensitivity{1.0f};
std::atomic<int> g_source{CEMU_BRIDGE_MOTION_SOURCE_DEVICE};
std::atomic<uint32_t> g_recenter{0};
std::atomic<int> g_orientation{(int)UIInterfaceOrientationLandscapeRight};
std::atomic<double> g_lastPoll{0.0};
std::atomic<bool> g_sensorsRunning{false};
std::atomic<bool> g_wakePending{false};
std::atomic<double> g_lastWake{0.0};

// Main thread only.
CMMotionManager* g_manager = nil;
NSOperationQueue* g_queue = nil;
GCController* g_controller = nil;
bool g_deviceRunning = false;
bool g_loggedDevice = false;

struct Samples {
    std::mutex mutex;
    double sumAcc[3] = {0, 0, 0};
    double sumGyro[3] = {0, 0, 0};
    int count = 0;
    bool haveData = false;
    float lastAcc[3] = {0, 1, 0};
    float lastGyro[3] = {0, 0, 0};
    double lastDataTime = 0;
    double lastOutTime = 0;
};
Samples g_samples;

double Now()
{
    return NSProcessInfo.processInfo.systemUptime;
}

// Reading in the device's own frame -> the screen's frame (right, up, out of the screen).
void DeviceToScreen(UIInterfaceOrientation orientation, const double d[3], double s[3])
{
    switch (orientation)
    {
    case UIInterfaceOrientationLandscapeRight: // home indicator on the right: the device's top points left
        s[0] = -d[1]; s[1] = d[0]; s[2] = d[2];
        break;
    case UIInterfaceOrientationLandscapeLeft: // home indicator on the left: the device's top points right
        s[0] = d[1]; s[1] = -d[0]; s[2] = d[2];
        break;
    case UIInterfaceOrientationPortraitUpsideDown:
        s[0] = -d[0]; s[1] = -d[1]; s[2] = d[2];
        break;
    default:
        s[0] = d[0]; s[1] = d[1]; s[2] = d[2];
        break;
    }
}

// One sensor reading in the screen frame. `reading` is gravity plus movement in g (pointing
// toward the ground when still), `rate` the angular velocity in rad/s.
void Submit(const double reading[3], const double rate[3])
{
    const double acc[3] = {reading[0], -reading[2], reading[1]};
    const double gyro[3] = {rate[0], -rate[2], rate[1]};
    std::lock_guard lock(g_samples.mutex);
    for (int i = 0; i < 3; ++i)
    {
        g_samples.sumAcc[i] += acc[i];
        g_samples.sumGyro[i] += gyro[i];
    }
    ++g_samples.count;
    g_samples.lastDataTime = Now();
}

void HandleDeviceMotion(CMDeviceMotion* motion)
{
    const auto orientation = (UIInterfaceOrientation)g_orientation.load(std::memory_order_relaxed);
    const double reading[3] = {
        motion.gravity.x + motion.userAcceleration.x,
        motion.gravity.y + motion.userAcceleration.y,
        motion.gravity.z + motion.userAcceleration.z,
    };
    const double rate[3] = {motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z};
    double screenReading[3], screenRate[3];
    DeviceToScreen(orientation, reading, screenReading);
    DeviceToScreen(orientation, rate, screenRate);
    Submit(screenReading, screenRate);
}

// A controller is treated like a phone lying on its back: the face buttons are the screen and
// the triggers are the top edge, which is how GameController reports its motion.
void HandleControllerMotion(GCMotion* motion)
{
    double reading[3];
    if (motion.hasGravityAndUserAcceleration)
    {
        reading[0] = motion.gravity.x + motion.userAcceleration.x;
        reading[1] = motion.gravity.y + motion.userAcceleration.y;
        reading[2] = motion.gravity.z + motion.userAcceleration.z;
    }
    else
    {
        reading[0] = motion.acceleration.x;
        reading[1] = motion.acceleration.y;
        reading[2] = motion.acceleration.z;
    }
    const double rate[3] = {
        motion.hasRotationRate ? motion.rotationRate.x : 0.0,
        motion.hasRotationRate ? motion.rotationRate.y : 0.0,
        motion.hasRotationRate ? motion.rotationRate.z : 0.0,
    };
    Submit(reading, rate);
}

void RefreshOrientation()
{
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;
        UIWindowScene* windowScene = (UIWindowScene*)scene;
        // An external display's scene always reports landscape; the device's own decides.
        if (windowScene.screen != UIScreen.mainScreen)
            continue;
        const UIInterfaceOrientation orientation = windowScene.interfaceOrientation;
        if (orientation != UIInterfaceOrientationUnknown)
        {
            g_orientation.store((int)orientation, std::memory_order_relaxed);
            return;
        }
    }
}

GCController* FindControllerWithMotion()
{
    for (GCController* controller in [GCController controllers])
    {
        if (controller.motion)
            return controller;
    }
    return nil;
}

void StopDevice()
{
    if (!g_deviceRunning)
        return;
    [g_manager stopDeviceMotionUpdates];
    g_deviceRunning = false;
}

void StopController()
{
    if (!g_controller)
        return;
    GCMotion* motion = g_controller.motion;
    motion.valueChangedHandler = nil;
    if (motion.sensorsRequireManualActivation)
        motion.sensorsActive = NO;
    g_controller = nil;
}

void StartController(GCController* controller)
{
    GCMotion* motion = controller.motion;
    if (motion.sensorsRequireManualActivation)
        motion.sensorsActive = YES;
    motion.valueChangedHandler = ^(GCMotion* changed) { HandleControllerMotion(changed); };
    g_controller = controller;
    cemu_bridge_log_line("iOS motion: using the motion sensors of a connected controller");
}

void StartDevice()
{
    if (g_deviceRunning)
        return;
    if (!g_manager)
        g_manager = [[CMMotionManager alloc] init];
    if (!g_manager.deviceMotionAvailable)
        return;
    if (!g_queue)
    {
        g_queue = [[NSOperationQueue alloc] init];
        g_queue.name = @"MuffinEMU motion";
        g_queue.maxConcurrentOperationCount = 1;
        g_queue.qualityOfService = NSQualityOfServiceUserInteractive;
    }
    g_manager.deviceMotionUpdateInterval = kUpdateInterval;
    [g_manager startDeviceMotionUpdatesToQueue:g_queue
                                   withHandler:^(CMDeviceMotion* motion, NSError* error) {
        (void)error;
        if (motion)
            HandleDeviceMotion(motion);
    }];
    g_deviceRunning = true;
    if (!g_loggedDevice)
    {
        g_loggedDevice = true;
        cemu_bridge_log_line("iOS motion: using this device's gyroscope and accelerometer");
    }
}

// Brings the sensors in line with the settings and with whether a title is reading them.
// Main thread only.
void Apply()
{
    RefreshOrientation();

    const bool idle = Now() - g_lastPoll.load() > kIdleSeconds;
    const bool active = g_enabled.load() && !idle;
    if (!active)
    {
        StopDevice();
        StopController();
        g_sensorsRunning.store(false);
        return;
    }

    GCController* motionController = g_source.load() == CEMU_BRIDGE_MOTION_SOURCE_CONTROLLER ? FindControllerWithMotion() : nil;
    if (motionController)
    {
        StopDevice();
        if (g_controller != motionController)
        {
            StopController();
            StartController(motionController);
        }
    }
    else
    {
        StopController();
        StartDevice();
    }
    g_sensorsRunning.store(g_deviceRunning || g_controller != nil);
}

void ApplyOnMain()
{
    if ([NSThread isMainThread])
        Apply();
    else
        dispatch_async(dispatch_get_main_queue(), ^{ Apply(); });
}

} // namespace

void IOSMotion_Start(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) { (void)note; Apply(); }];
            [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) {
                                (void)note;
                                // The controller is gone: drop it before Apply() looks for another.
                                StopController();
                                Apply();
                            }];
            // The interface orientation has no notification that is not deprecated, and it only
            // changes when the player turns the device, so a slow timer is enough. The same tick
            // puts the sensors to sleep when no title has read them for a while.
            [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer* timer) { (void)timer; Apply(); }];
            Apply();
        });
    });
}

void IOSMotion_Poll(IOSMotionSample* out)
{
    if (!out)
        return;
    const double now = Now();
    g_lastPoll.store(now);
    IOSMotion_Start();
    const bool enabled = g_enabled.load();
    // At most once a second, so a device with no motion sensors does not hop to the main thread on every read.
    if (enabled && !g_sensorsRunning.load() && now - g_lastWake.load() >= 1.0 && !g_wakePending.exchange(true))
    {
        g_lastWake.store(now);
        dispatch_async(dispatch_get_main_queue(), ^{
            g_wakePending.store(false);
            Apply();
        });
    }

    const float sensitivity = std::clamp(g_sensitivity.load(), kMinSensitivity, kMaxSensitivity);
    std::lock_guard lock(g_samples.mutex);
    double timestamp;
    if (!enabled)
    {
        // A GamePad lying flat and still. Gravity along Y is the handler's default pose.
        g_samples.lastAcc[0] = 0.0f; g_samples.lastAcc[1] = 1.0f; g_samples.lastAcc[2] = 0.0f;
        g_samples.lastGyro[0] = g_samples.lastGyro[1] = g_samples.lastGyro[2] = 0.0f;
        g_samples.count = 0;
        g_samples.haveData = false;
        timestamp = now;
    }
    else if (g_samples.count > 0)
    {
        const double n = (double)g_samples.count;
        for (int i = 0; i < 3; ++i)
        {
            g_samples.lastAcc[i] = (float)(g_samples.sumAcc[i] / n);
            g_samples.lastGyro[i] = (float)(g_samples.sumGyro[i] / n);
            g_samples.sumAcc[i] = g_samples.sumGyro[i] = 0.0;
        }
        g_samples.count = 0;
        g_samples.haveData = true;
        timestamp = g_samples.lastDataTime;
    }
    else if (g_samples.haveData)
    {
        // Nothing new since the last read: same values, same timestamp, and the core keeps what it had.
        timestamp = g_samples.lastDataTime;
    }
    else
    {
        // No sensors (or none started yet): a still GamePad, so a title never waits on motion.
        g_samples.lastAcc[0] = 0.0f; g_samples.lastAcc[1] = 1.0f; g_samples.lastAcc[2] = 0.0f;
        g_samples.lastGyro[0] = g_samples.lastGyro[1] = g_samples.lastGyro[2] = 0.0f;
        timestamp = now;
    }
    // The core ignores a sample that is not newer than the last one it took.
    if (timestamp < g_samples.lastOutTime)
        timestamp = g_samples.lastOutTime;
    g_samples.lastOutTime = timestamp;

    for (int i = 0; i < 3; ++i)
    {
        out->accelerometer[i] = g_samples.lastAcc[i];
        out->gyroscope[i] = g_samples.lastGyro[i] * sensitivity;
    }
    out->timestamp = timestamp;
    out->recenterCount = g_recenter.load();
}

void cemu_bridge_set_motion_enabled(bool enabled)
{
    g_enabled.store(enabled);
    ApplyOnMain();
}

void cemu_bridge_set_motion_sensitivity(float sensitivity)
{
    if (!std::isfinite(sensitivity))
        return;
    g_sensitivity.store(std::clamp(sensitivity, kMinSensitivity, kMaxSensitivity));
}

void cemu_bridge_set_motion_source(int source)
{
    g_source.store(source == CEMU_BRIDGE_MOTION_SOURCE_CONTROLLER ? CEMU_BRIDGE_MOTION_SOURCE_CONTROLLER
                                                                  : CEMU_BRIDGE_MOTION_SOURCE_DEVICE);
    ApplyOnMain();
}

void cemu_bridge_motion_recenter(void)
{
    g_recenter.fetch_add(1);
}

bool cemu_bridge_motion_controller_available(void)
{
    if (![NSThread isMainThread])
        return false; // GameController objects are main-thread only; the Settings screen asks from there
    return FindControllerWithMotion() != nil;
}

int cemu_bridge_motion_status(void)
{
    if (!g_enabled.load())
        return CEMU_BRIDGE_MOTION_STATUS_OFF;
    if (g_source.load() == CEMU_BRIDGE_MOTION_SOURCE_CONTROLLER && cemu_bridge_motion_controller_available())
        return CEMU_BRIDGE_MOTION_STATUS_CONTROLLER;
    static bool available = false;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ available = [[CMMotionManager alloc] init].deviceMotionAvailable; });
    return available ? CEMU_BRIDGE_MOTION_STATUS_DEVICE : CEMU_BRIDGE_MOTION_STATUS_UNAVAILABLE;
}
