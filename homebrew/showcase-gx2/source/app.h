// Shared types and globals for the MuffinEMU showcase RPX.
//
// Everything in this program is procedural: no image, model or sound file is
// bundled or loaded. Geometry, textures, fonts and music are generated in code
// at startup, so the RPX runs standalone with no SD card or content folder.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <vpad/input.h>

// Virtual screen space for all 2D drawing. Both the TV and the GamePad are 16:9,
// so the same layout is stretched onto either.
#define VW 1280.0f
#define VH 720.0f

#define PI_F 3.14159265358979f

typedef enum { TARGET_TV = 0, TARGET_DRC = 1 } Target;

typedef struct
{
   bool ok;          // a fresh GamePad sample arrived this frame
   uint32_t hold, trig, rel;
   float lx, ly, rx, ry;       // sticks, -1..1, y up
   bool touch, touchStart;
   float tx, ty;               // touch in virtual 1280x720 space
   float ax, ay, az;           // accelerometer, 1.0 = 1 g
   float gx, gy, gz;           // gyro rate, 1.0 = 360 deg/s
   float angx, angy, angz;     // integrated gyro angle, 1.0 = 360 deg
} Input;

extern Input g_in;
extern double g_time;   // seconds since boot
extern float g_dt;      // last frame time, seconds
extern float g_fps;     // smoothed
extern bool g_hud;      // PLUS toggles all text/overlays
extern bool g_tour;     // auto-tour running

#define PRESSED(btn) ((g_in.trig & (btn)) != 0)
#define HELD(btn)    ((g_in.hold & (btn)) != 0)

typedef struct
{
   const char *name;     // short title
   const char *feat;     // one line: what this one demonstrates
   void (*enter)(void);
   void (*leave)(void);
   void (*update)(float dt);   // logic, and build geometry shared by both screens
   void (*prepass)(void);      // optional: offscreen render passes, before either screen
   void (*draw)(Target t);     // draw one screen, including its HUD
   float tourSeconds;
} Scene;

extern const Scene scene_hub, scene_world, scene_particles, scene_fx, scene_mirror,
                   scene_fractal, scene_input, scene_sound, scene_system;

// Scene 0 is the menu, 1.. are the showcases.
#define SCENE_COUNT 9
const Scene *app_scene(int index);
void app_goto(int index);
int app_current(void);
float app_scene_time(void);
void fractal_quit(void);
