// MuffinEMU Showcase - shared declarations. MPL-2.0, original code.
#ifndef SHOWCASE_H
#define SHOWCASE_H

#include <stdint.h>
#include <stddef.h>

typedef uint8_t  u8;
typedef int8_t   s8;
typedef int16_t  s16;
typedef uint16_t u16;
typedef int32_t  s32;
typedef uint32_t u32;

#define TV_W      1280
#define TV_H      720
#define DRC_W     854
#define DRC_H     480
#define DRC_PITCH 896
#define SCN_W     640   // largest internal scene buffer (2x upscaled to the TV)
#define SCN_H     360
#define REF_W     320   // reference grid that scene coordinates were authored on (4x quality)
#define REF_H     180

// OSScreen pixels are RGBX8888 in PPC (big-endian) word order.
#define RGB(r, g, b) ((((u32)(r)) << 24) | (((u32)(g)) << 16) | (((u32)(b)) << 8) | 0xFFu)
#define CR(c) (((c) >> 24) & 255u)
#define CG(c) (((c) >> 16) & 255u)
#define CB(c) (((c) >> 8) & 255u)

#define COL_BG      RGB(10, 8, 24)
#define COL_PANEL   RGB(20, 16, 44)
#define COL_ACCENT  RGB(255, 170, 60)
#define COL_CYAN    RGB(90, 225, 255)
#define COL_PINK    RGB(255, 90, 170)
#define COL_WHITE   RGB(245, 245, 255)
#define COL_DIM     RGB(140, 135, 175)
#define COL_GREEN   RGB(110, 240, 140)
#define COL_RED     RGB(255, 90, 90)

#define PI_F 3.14159265f
#define TAU_F 6.28318531f

// ---------------------------------------------------------------- util.c
void  util_init(void);
u32   col_lerp(u32 a, u32 b, int t256);   // packed two-multiply blend, t 0..256
u32   col_avg(u32 a, u32 b);              // (a+b)/2 with no overflow between channels
float m_sin(float x);
float m_cos(float x);
float m_sqrt(float x);
float m_atan2(float y, float x);
float m_exp2(float x);
int   m_floor(float x);
float m_abs(float x);
float m_clamp(float x, float lo, float hi);
float m_mix(float a, float b, float t);
u32   rnd(void);
float frand(void);                 // 0..1
float frands(void);                // -1..1
u32   rnd_r(u32 *state);
u32   hash2(int x, int y);
u32   col_mix(u32 a, u32 b, int t256);
u32   col_add(u32 a, u32 b);
u32   col_scale(u32 c, int k256);
u32   hsv(float h, float s, float v);

// ---------------------------------------------------------------- gfx.c
typedef struct { u32 *p; int pitch, w, h; } Surf;
extern Surf S_TV, S_DRC, S_SCN;
extern int  g_scale, g_sw, g_sh;
void gfx_init(void);
void gfx_set_scale(int scale);      // 2 (640x360), 4 (320x180) or 8 (160x90)
void gfx_upsample(const u32 *lo, int lw, int lh, int bx, int by);   // bilinear lo-res grid -> S_SCN
void gfx_begin_frame(void);
void gfx_present_scene(void);       // S_SCN -> TV back buffer (upscaled)
void gfx_flip_tv(void);
void gfx_blit_scene_drc(int x0, int y0);   // second view: scene pixel-doubled to 640x360
void gfx_flip_drc(void);
void s_fill(Surf *s, u32 c);
void s_rect(Surf *s, int x, int y, int w, int h, u32 c);
void s_rect_a(Surf *s, int x, int y, int w, int h, u32 c, int a);
void s_vgrad(Surf *s, int x, int y, int w, int h, u32 c0, u32 c1);
void s_hline(Surf *s, int x, int y, int w, u32 c);
void s_vline(Surf *s, int x, int y, int h, u32 c);
void s_line(Surf *s, int x0, int y0, int x1, int y1, u32 c);
void s_disc(Surf *s, int cx, int cy, int r, u32 c);
void s_ring(Surf *s, int cx, int cy, int r, u32 c);
void s_tri(Surf *s, int x0, int y0, int x1, int y1, int x2, int y2, u32 c);
void s_box_outline(Surf *s, int x, int y, int w, int h, u32 c);
void s_text(Surf *s, int x, int y, int scale, u32 c, const char *str);
void s_text_sh(Surf *s, int x, int y, int scale, u32 c, const char *str);
void s_textf(Surf *s, int x, int y, int scale, u32 c, const char *fmt, ...);
int  text_w(const char *str, int scale);
void s_fade(Surf *s, int k256);     // multiply every pixel by k/256
void s_add_pixel(Surf *s, int x, int y, u32 c);
void s_panel(Surf *s, int x, int y, int w, int h, u32 border);
void s_blob(Surf *s, int cx, int cy, int rx, int ry, u32 c, int a256);   // soft additive-free glow, centre alpha a
void s_glow(Surf *s, int cx, int cy, int r, u32 c, int k256);           // additive radial glow
void s_line_aa(Surf *s, float x0, float y0, float x1, float y1, u32 c);  // anti-aliased line
void s_disc_aa(Surf *s, float cx, float cy, float r, u32 c);            // anti-aliased disc
void s_blend_pixel(Surf *s, int x, int y, u32 c, int a256);
void s_edge_aa(Surf *s, int y0, int y1);                                // cheap edge smoothing on rows y0..y1-1

// ---------------------------------------------------------------- par.c
#define PAR_JOBS 3
void par_init(void);
void par_run(void (*fn)(void *ctx, int job, int njobs), void *ctx);
void par_shutdown(void);
void par_publish(const void *p, size_t n);   // main: flush data the slices will read
void par_flush(const void *p, size_t n);     // slice: write back what this core produced
void par_consume(const void *p, size_t n);   // any core: drop stale cache lines before reading
static inline void par_range(int job, int njobs, int n, int *a, int *b) { *a = n * job / njobs; *b = n * (job + 1) / njobs; }

// ---------------------------------------------------------------- input.c
typedef struct {
   u32 hold, trig;                  // VPAD_BUTTON_* bits (GamePad and Pro merged)
   float lx, ly, rx, ry;            // sticks, y up positive
   int touched, touch_trig;
   float tx, ty;                    // GamePad pixels (854x480)
   float acc[3], gyro[3], ang[3];
   int pro, vpad_ok;
   int any;                         // any deliberate input this frame
} Input;
void input_init(void);
void input_poll(Input *in);
void input_rumble(int bits);
void input_rumble_stop(void);

// Button bits (same values as VPAD_BUTTON_*, kept here so scene code does not need the wut headers).
#define B_A 0x8000u
#define B_B 0x4000u
#define B_X 0x2000u
#define B_Y 0x1000u
#define B_LEFT 0x0800u
#define B_RIGHT 0x0400u
#define B_UP 0x0200u
#define B_DOWN 0x0100u
#define B_ZL 0x0080u
#define B_ZR 0x0040u
#define B_L 0x0020u
#define B_R 0x0010u
#define B_PLUS 0x0008u
#define B_MINUS 0x0004u
#define B_STICK_R 0x00020000u
#define B_STICK_L 0x00040000u

// ---------------------------------------------------------------- audio.c
#define NUM_TRACKS 5
#define EV_KICK 1
#define EV_SNARE 2
#define EV_HAT 4
#define EV_BASS 8
#define EV_LEAD 16
#define EV_ARP 32
void  audio_init(void);
void  audio_shutdown(void);
void  audio_update(float dt);
void  audio_set_track(int t);
int   audio_track(void);
int   audio_ready(int t);
int   audio_progress(void);          // 0..100 background render progress
void  audio_set_mute(int m);
int   audio_muted(void);
void  audio_set_volume(float v);
float audio_volume(void);
int   audio_step(void);              // 0..63 playhead
float audio_step_frac(void);
const char *audio_track_name(int t);
int   audio_track_bpm(int t);
u8    audio_event(int t, int step);  // EV_* mask
int   audio_lead_note(int t, int step); // -1 = rest, else semitone offset from track root
const s16 *audio_pcm(int t, int *len);
int   audio_pcm_pos(void);           // sample index currently playing, or -1

// ---------------------------------------------------------------- scenes
typedef struct {
   const char *name;
   const char *blurb;
   int track;
   void (*enter)(void);
   void (*update)(const Input *in, float dt, int demo);
   void (*render)(void);             // draws into S_SCN
   void (*hud)(void);                // draws onto S_TV after upscale
   void (*drc)(const Input *in);     // draws the whole GamePad screen
} Scene;

#define NUM_SCENES 7
extern const Scene *const g_scenes[NUM_SCENES];
extern const Scene sc_landscape, sc_particles, sc_shader, sc_inputlab, sc_audio, sc_stress, sc_mesh;

// Global state shared between main and the scenes.
typedef struct {
   float fps, frame_ms, update_ms, render_ms, present_ms;
   float hist[120];
   int   hist_pos;
} Stats;
extern Stats g_stats;
extern float g_time;
extern int   g_demo;
extern int   g_frame;
extern int   g_audio_track_override;   // -1 = follow the scene
void terrain_gen_step(int rows);       // background heightmap generation (title screen)
int  terrain_ready(void);
void draw_muffin(Surf *s, int cx, int cy, int sz);
void stress_start_workers(void);
void stress_stop_workers(void);
void draw_hud_common(const char *name, const char *hint);

#endif
