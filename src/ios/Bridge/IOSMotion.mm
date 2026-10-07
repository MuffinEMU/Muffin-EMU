// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  IOSMotion.mm
//  Motion for the emulated GamePad. See IOSMotion.h.
//
//  The GamePad's frame, as the console and the core's motion handler see it (the same one a
//  DualShock/DualSense reports in when it lies face up):
//    X  to the right of the screen
//    Y  out of the screen, toward the ceiling when the pad lies flat
//    Z  toward the bottom edge of the screen, toward the player when the pad lies flat
//  (right-handed: X cross Y = Z). A flat pad reads gravity along +Y, and the handler's default
//  pose (MahonySensorFusion's starting quaternion, which is also the identity attitude matrix in
//  the real-console captures at the bottom of MotionSample.h) is exactly that.
//
//  Devices report in their own frame. CoreMotion: X right, Y toward the top of the device in
//  portrait, Z out of the screen, right-handed; `gravity + userAcceleration` is the vector
//  toward the ground (-Z when the device lies face up), rotationRate is rad/s, counter-clockwise
//  positive about each axis. Three steps connect the two:
//
//  1. DEVICE -> SCREEN frame (right, up, out of the screen) for the interface orientation, so the
//     same tilt means the same thing in every orientation. Apply the same rotation to the ground
//     vector and to the angular rate (a pure rotation, so both transform alike):
//
//       interface orientation                  screen.x  screen.y  screen.z
//       Portrait                                 d.x       d.y       d.z
//       PortraitUpsideDown                      -d.x      -d.y       d.z
//       LandscapeLeft  (home on the left,        d.y      -d.x       d.z
//                       device top points right)
//       LandscapeRight (home on the right,      -d.y       d.x       d.z
//                       device top points left)
//
//     UIInterfaceOrientation, not UIDeviceOrientation: the two names are swapped for the
//     landscapes, and the picture on screen follows the interface.
//
//  2. SCREEN -> GamePad frame. screen (x, y, z) is (right, up, out) and the pad is (right, out,
//     bottom), so a vector v in the screen frame is (v.x, v.z, -v.y) in the pad frame.
//
//  3. PAD -> handler. The core's SDL path (SDLControllerProvider.cpp) hands the motion handler
//     the raw controller readings with the X axis mirrored: acc = (-f.x, f.y, f.z) for the
//     accelerometer's specific force f (which points away from the ground), and gyro = (w.x,
//     -w.y, -w.z) for the angular rate w. Mirroring one axis makes the frame left-handed, and an
//     angular rate is a pseudovector, so it picks up the determinant's extra sign: the two
//     together are consistent and the handler's fusion agrees with itself.
//
//  Our ground vector r is -f, so putting steps 2 and 3 together, for a screen-frame r and rate w:
//       acc  = ( r.x, -r.z,  r.y)
//       gyro = ( w.x, -w.z,  w.y)
//
//  Checked against the real-console captures in MotionSample.h, for a pad starting flat and
//  screen up, top edge away (handler input -> attitude the handler produces):
//       tilt the top edge up 90 deg : w.x > 0, acc (0, 0, -1) -> matches "tilt up 90"
//       turn 45 deg to the right    : w.z < 0 (clockwise from above), gyro.y > 0, acc stays
//                                     (0, 1, 0) -> matches "turned 45 deg to the right"
//       lean on its left side 45 deg: w.y < 0, gyro.z < 0, acc (-.71, .71, 0) -> matches "lean
//                                     on its left side"
//  and in each case the fusion's gravity estimate equals the acc given, so nothing fights the gyro.
//
//  A controller's own motion (GCMotion) uses CoreMotion's conventions with the controller lying
//  face up like a phone on its back (X right, Y toward the triggers, Z out of the face), so it
//  skips step 1.
//
//  The rate is scaled by the sensitivity before fusion. The fusion slowly pulls the pose toward
//  gravity, so a high sensitivity is pulled back a little; the core offers no way around that.
//
//  Device test, if aim ever feels wrong (Settings > Motion & Aiming > "Log motion values" writes
//  a line a second to the engine log: raw device values, screen values, what the core gets):
//    hold the device flat, screen up, top edge away, then
//      raise the top edge   -> "gyro" x positive
//      turn clockwise       -> "gyro" y positive
//      lower the left edge  -> "gyro" z negative
//    and lying flat "acc" should read about (0, 1, 0).
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
#include <cstdio>
#include <mutex>

#include "IOSMotion.h"
#include "CemuBridge.h"

namespace {

constexpr double kUpdateInterval = 1.0 / 100.0; // the fastest CoreMotion delivers device motion
constexpr double kIdleSeconds = 3.0;            // no VPADRead for this long: stop the sensors
constexpr double kDiagnosticInterval = 1.0;     // seconds between "Log motion values" lines
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
std::atomic<bool> g_invertHorizontal{false};
std::atomic<bool> g_invertVertical{false};
std::atomic<bool> g_diagnostic{false};
// Set whenever the pose the core has been tracking can no longer be trusted: the sensors just
// (re)started, the interface turned to another orientation. The next real sample then bumps
// g_recenter, which makes the core restart its orientation estimate from that sample's gravity
// instead of swinging round from wherever it was.
std::atomic<bool> g_needSeed{true};

// Main thread only.
CMMotionManager* g_manager = nil;
NSOperationQueue* g_queue = nil;
GCController* g_controller = nil;
bool g_deviceRunning = false;
bool g_loggedDevice = false;
bool g_inBackground = false;

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
    double lastDiagTime = 0;
};
Samples g_samples;

double Now()
{
    return NSProcessInfo.processInfo.systemUptime;
}

bool AllFinite(const double v[3])
{
    return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]);
}

// Reading in the device's own frame -> the screen's frame (right, up, out of the screen).
// The table is in the comment at the top of the file.
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

// The aim-direction switches in Settings. They exist so a device test can settle a direction
// that feels backwards without a new build; the mapping itself is derived above. Horizontal
// reverses the turn about the vertical (gravity) axis, whichever way the device is held; vertical
// reverses the tilt about the screen's own left-right axis. Only the rate is changed, so the
// fusion's gravity correction pulls against a reversed pitch: fine for finding out which way is
// right, not meant as a permanent setting.
void ApplyInversion(const double reading[3], double rate[3])
{
    if (g_invertVertical.load(std::memory_order_relaxed))
        rate[0] = -rate[0];
    if (g_invertHorizontal.load(std::memory_order_relaxed))
    {
        const double length = std::sqrt(reading[0] * reading[0] + reading[1] * reading[1] + reading[2] * reading[2]);
        if (length > 0.3)
        {
            const double u[3] = {reading[0] / length, reading[1] / length, reading[2] / length};
            const double along = rate[0] * u[0] + rate[1] * u[1] + rate[2] * u[2];
            for (int i = 0; i < 3; ++i)
                rate[i] -= 2.0 * along * u[i];
        }
    }
}

// One sensor reading in the screen frame. `reading` is gravity plus movement in g (pointing
// toward the ground when still), `rate` the angular velocity in rad/s, `timestamp` when the
// sensor took it (seconds on the systemUptime clock). `rawReading`/`rawRate` are the same
// values before any turning, kept only for the diagnostic line.
void Submit(const char* source, const double rawReading[3], const double rawRate[3],
            const double reading[3], const double rateIn[3], double timestamp)
{
    // One NaN would poison the core's orientation estimate for good; drop the sample instead.
    if (!AllFinite(reading) || !AllFinite(rateIn) || !std::isfinite(timestamp))
        return;
    double rate[3] = {rateIn[0], rateIn[1], rateIn[2]};
    ApplyInversion(reading, rate);

    const double acc[3] = {reading[0], -reading[2], reading[1]};
    const double gyro[3] = {rate[0], -rate[2], rate[1]};
    const double now = Now();
    bool logNow = false;
    {
        std::lock_guard lock(g_samples.mutex);
        if (g_needSeed.exchange(false))
            g_recenter.fetch_add(1);
        for (int i = 0; i < 3; ++i)
        {
            g_samples.sumAcc[i] += acc[i];
            g_samples.sumGyro[i] += gyro[i];
        }
        ++g_samples.count;
        g_samples.lastDataTime = std::max(g_samples.lastDataTime, timestamp);
        if (g_diagnostic.load(std::memory_order_relaxed) && now - g_samples.lastDiagTime >= kDiagnosticInterval)
        {
            g_samples.lastDiagTime = now;
            logNow = true;
        }
    }
    if (logNow)
    {
        char line[400];
        snprintf(line, sizeof line,
                 "iOS motion values (%s, orientation %d): device grav %.2f %.2f %.2f rate %.2f %.2f %.2f | "
                 "screen grav %.2f %.2f %.2f rate %.2f %.2f %.2f | core acc %.2f %.2f %.2f gyro %.2f %.2f %.2f "
                 "| invert h=%d v=%d",
                 source, g_orientation.load(),
                 rawReading[0], rawReading[1], rawReading[2], rawRate[0], rawRate[1], rawRate[2],
                 reading[0], reading[1], reading[2], rateIn[0], rateIn[1], rateIn[2],
                 acc[0], acc[1], acc[2], gyro[0], gyro[1], gyro[2],
                 g_invertHorizontal.load() ? 1 : 0, g_invertVertical.load() ? 1 : 0);
        cemu_bridge_log_line(line);
    }
}

// Forgets anything the previous run of the sensors left behind, so a new run starts clean.
void ResetSamples()
{
    std::lock_guard lock(g_samples.mutex);
    for (int i = 0; i < 3; ++i)
        g_samples.sumAcc[i] = g_samples.sumGyro[i] = 0.0;
    g_samples.count = 0;
    g_samples.haveData = false;
    g_needSeed.store(true);
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
    // The sensor's own timestamp, not the time this block happened to run: the core integrates
    // the rate over the gap between samples, and delivery jitter would otherwise leak into it.
    Submit("device", reading, rate, screenReading, screenRate, motion.timestamp);
}

// A controller is treated like a phone lying on its back: the face buttons are the screen and
// the triggers are the top edge, which is how GameController reports its motion. It has no
// interface orientation, so there is nothing to turn.
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
    // GCMotion carries no timestamp; the handler runs as the sample arrives.
    Submit("controller", reading, rate, reading, rate, Now());
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
            // Turning the device over changes what every axis means at once; start the core's
            // orientation estimate again from the new pose rather than let it swing round.
            if (g_orientation.exchange((int)orientation, std::memory_order_relaxed) != (int)orientation)
                g_needSeed.store(true);
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
    ResetSamples();
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
    ResetSamples();
}

void StartController(GCController* controller)
{
    ResetSamples();
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
    ResetSamples();
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
    // CoreMotion stops delivering while the app is in the background and does not promise to pick
    // up again by itself, so let go of the sensors there and start them afresh on return.
    const bool active = g_enabled.load() && !idle && !g_inBackground;
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
            [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) { (void)note; g_inBackground = true; Apply(); }];
            [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) { (void)note; g_inBackground = false; Apply(); }];
            g_inBackground = UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
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

void cemu_bridge_set_motion_invert(bool horizontal, bool vertical)
{
    g_invertHorizontal.store(horizontal);
    g_invertVertical.store(vertical);
}

void cemu_bridge_set_motion_diagnostic(bool enabled)
{
    g_diagnostic.store(enabled);
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
