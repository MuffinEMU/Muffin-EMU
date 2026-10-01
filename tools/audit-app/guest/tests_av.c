// tests_av.c - the audio and input tests of the audit guest.
//
// audio_sweep plays a looping sine table through one AX voice and sweeps its pitch. What reaches
// the device is measured inside the core (underruns, sample jumps, silence, level), and the
// Audit app asks the listener whether it sounded clean.
//
// input_echo reads the GamePad through VPAD every frame, publishes what it saw in the mailbox and
// draws it. The app drives the emulated pad (buttons, sticks, touch) and checks the mailbox; a
// person can also press real buttons or touch the screen and see them echoed.

#include "audit_internal.h"

#include <coreinit/thread.h>
#include <sndcore2/core.h>
#include <sndcore2/device.h>
#include <sndcore2/voice.h>
#include <vpad/input.h>

#include <malloc.h>
#include <math.h>
#include <stdio.h>

static const float kBg[4] = {0.05f, 0.05f, 0.08f, 1.0f};

// GCC folds sinf(x) and cosf(x) of the same x into sincosf(), which devkitPPC's newlib does not
// have; keeping the call in its own function stops the fold (same trick as the bench workloads).
static float __attribute__((noinline)) AuditSin(float x)
{
   return sinf(x);
}

// ---------------------------------------------------------------------------------------------
// audio_sweep

#define SINE_SAMPLES 64u

static void SceneAudio(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   // A bar whose length follows the step the sweep is on, so a capture shows where the test is.
   uint32_t step = MbGet(AUDIT_MB_AUDIO_STEP);
   DrawRect(0.1f, 0.45f, 0.8f, 0.10f, 0.5f, 0.12f, 0.12f, 0.16f, 1.0f);
   DrawRect(0.1f, 0.45f, 0.2f * (float)step, 0.10f, 0.5f, 0.2f, 0.8f, 0.4f, 1.0f);
   DrawRect(0.1f + 0.8f * (float)(frame % 120u) / 120.0f, 0.60f, 0.02f, 0.05f, 0.5f, 1, 1, 1, 1);
}

// Plays for `ms`, presenting frames, optionally moving the pitch from ratio r0 to r1.
static BOOL AudioPhase(Ctx *ctx, AXVoice *voice, uint32_t step, const char *name, uint32_t ms, float r0, float r1,
                       BOOL sounding)
{
   LogPhase(ctx, name);
   MbSet(AUDIT_MB_AUDIO_STEP, step);
   AXVoiceBegin(voice);
   AXSetVoiceState(voice, sounding ? AX_VOICE_STATE_PLAYING : AX_VOICE_STATE_STOPPED);
   AXSetVoiceSrcRatio(voice, r0);
   AXVoiceEnd(voice);

   OSTime start     = OSGetTime();
   uint32_t frame   = 0;
   OSTime lastStep  = start;
   for (;;) {
      uint32_t elapsed = (uint32_t)OSTicksToMilliseconds(OSGetTime() - start);
      if (elapsed >= ms) {
         break;
      }
      if (sounding && r1 != r0 && OSTicksToMilliseconds(OSGetTime() - lastStep) >= 50) {
         lastStep   = OSGetTime();
         float t    = (float)elapsed / (float)ms;
         AXVoiceBegin(voice);
         AXSetVoiceSrcRatio(voice, r0 + (r1 - r0) * t);
         AXVoiceEnd(voice);
      }
      if (!PresentFrame(ctx, kBg, SceneAudio, NULL, frame++)) {
         return FALSE;
      }
   }
   return TRUE;
}

static BOOL TestAudioSweep(Ctx *ctx)
{
   char fmtName[16] = "lpcm16";
   char devName[16] = "both";
   ParamStr(ctx, "format", fmtName, sizeof(fmtName));
   ParamStr(ctx, "device", devName, sizeof(devName));
   uint32_t toneMs  = (uint32_t)ParamInt(ctx, "toneMs", 1500);
   uint32_t sweepMs = (uint32_t)ParamInt(ctx, "sweepMs", 4000);
   uint32_t gapMs   = (uint32_t)ParamInt(ctx, "gapMs", 700);
   BOOL is8         = strcmp(fmtName, "lpcm8") == 0;
   BOOL useTv       = strcmp(devName, "drc") != 0;
   BOOL useDrc      = strcmp(devName, "tv") != 0;

   AXInitParams init = {0};
   init.renderer     = AX_INIT_RENDERER_48KHZ;
   init.pipeline     = AX_INIT_PIPELINE_SINGLE;
   AXInitWithParams(&init);

   uint32_t bytes = SINE_SAMPLES * (is8 ? 1u : 2u);
   void *data     = memalign(0x40, bytes);
   if (!data) {
      LogSelf(ctx, "fail", "could not allocate the sample table");
      AXQuit();
      return TRUE;
   }
   for (uint32_t i = 0; i < SINE_SAMPLES; i++) {
      float s = AuditSin(6.28318530718f * (float)i / (float)SINE_SAMPLES);
      if (is8) {
         ((int8_t *)data)[i] = (int8_t)(s * 90.0f);
      } else {
         ((int16_t *)data)[i] = (int16_t)(s * 12000.0f);
      }
   }

   AXVoice *voice = AXAcquireVoice(31, NULL, NULL);
   if (!voice) {
      LogSelf(ctx, "fail", "AXAcquireVoice returned no voice");
      free(data);
      AXQuit();
      return TRUE;
   }

   AXVoiceBegin(voice);
   AXVoiceOffsets offsets;
   memset(&offsets, 0, sizeof(offsets));
   offsets.dataType       = is8 ? AX_VOICE_FORMAT_LPCM8 : AX_VOICE_FORMAT_LPCM16;
   offsets.loopingEnabled = AX_VOICE_LOOP_ENABLED;
   offsets.loopOffset     = 0;
   offsets.endOffset      = SINE_SAMPLES - 1;
   offsets.currentOffset  = 0;
   offsets.data           = data;
   AXSetVoiceOffsets(voice, &offsets);

   AXVoiceVeData ve = {0x8000, 0};
   AXSetVoiceVe(voice, &ve);

   AXVoiceDeviceMixData mix;
   memset(&mix, 0, sizeof(mix));
   mix.bus[0].volume = 0x8000;
   if (useTv) {
      AXSetVoiceDeviceMix(voice, AX_DEVICE_TYPE_TV, 0, &mix);
   }
   if (useDrc) {
      AXSetVoiceDeviceMix(voice, AX_DEVICE_TYPE_DRC, 0, &mix);
   }
   AXSetVoiceSrcType(voice, AX_VOICE_SRC_TYPE_LINEAR);
   AXSetVoiceSrcRatio(voice, 1.0f);
   AXSetVoiceState(voice, AX_VOICE_STATE_STOPPED);
   AXVoiceEnd(voice);

   LogNote(ctx, "format=%s device=%s toneMs=%u sweepMs=%u gapMs=%u", fmtName, devName, (unsigned)toneMs,
           (unsigned)sweepMs, (unsigned)gapMs);
   MbSet(AUDIT_MB_AUDIO_STATE, 1);

   // Steps: 1 fixed tone, 2 sweep up, 3 sweep down, 4 silence. The app snapshots the audio
   // counters whenever the step changes and judges each window on its own.
   BOOL ok = AudioPhase(ctx, voice, 1, "tone", toneMs, 1.0f, 1.0f, TRUE) &&
             AudioPhase(ctx, voice, 2, "sweep_up", sweepMs, 0.5f, 2.0f, TRUE) &&
             AudioPhase(ctx, voice, 3, "sweep_down", sweepMs, 2.0f, 0.5f, TRUE) &&
             AudioPhase(ctx, voice, 4, "silence", gapMs, 1.0f, 1.0f, FALSE);
   MbSet(AUDIT_MB_AUDIO_STEP, 5);
   MbSet(AUDIT_MB_AUDIO_STATE, 2);

   AXVoiceBegin(voice);
   AXSetVoiceState(voice, AX_VOICE_STATE_STOPPED);
   AXVoiceEnd(voice);
   AXFreeVoice(voice);
   AXQuit();
   free(data);
   Fold(ctx, toneMs + sweepMs);
   return ok;
}

// ---------------------------------------------------------------------------------------------
// input_echo

typedef struct InputView
{
   uint32_t hold;
   float lx, ly, rx, ry;
   BOOL touched;
   float tx, ty; // 0..1 across the screen
} InputView;

static void SceneInput(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)frame;
   const InputView *v = (const InputView *)user;
   static const uint32_t kButtons[16] = {
      VPAD_BUTTON_A,    VPAD_BUTTON_B,    VPAD_BUTTON_X,     VPAD_BUTTON_Y,     VPAD_BUTTON_L,    VPAD_BUTTON_R,
      VPAD_BUTTON_ZL,   VPAD_BUTTON_ZR,   VPAD_BUTTON_PLUS,  VPAD_BUTTON_MINUS, VPAD_BUTTON_UP,   VPAD_BUTTON_DOWN,
      VPAD_BUTTON_LEFT, VPAD_BUTTON_RIGHT, VPAD_BUTTON_STICK_L, VPAD_BUTTON_STICK_R};
   for (uint32_t i = 0; i < 16; i++) {
      BOOL on = (v->hold & kButtons[i]) != 0;
      DrawRect(0.06f + (float)(i % 8) * 0.11f, 0.08f + (float)(i / 8) * 0.14f, 0.09f, 0.10f, 0.5f, on ? 0.2f : 0.15f,
               on ? 0.9f : 0.15f, on ? 0.3f : 0.18f, 1.0f);
   }
   // Two stick wells with a dot each.
   DrawRect(0.10f, 0.45f, 0.30f, 0.50f, 0.6f, 0.12f, 0.12f, 0.16f, 1.0f);
   DrawRect(0.60f, 0.45f, 0.30f, 0.50f, 0.6f, 0.12f, 0.12f, 0.16f, 1.0f);
   DrawRect(0.25f + v->lx * 0.13f - 0.015f, 0.70f - v->ly * 0.20f - 0.03f, 0.03f, 0.06f, 0.4f, 1, 1, 1, 1);
   DrawRect(0.75f + v->rx * 0.13f - 0.015f, 0.70f - v->ry * 0.20f - 0.03f, 0.03f, 0.06f, 0.4f, 1, 1, 1, 1);
   if (v->touched) {
      DrawRect(v->tx - 0.02f, v->ty - 0.035f, 0.04f, 0.07f, 0.3f, 1.0f, 0.3f, 0.0f, 1.0f);
   }
}

static int32_t ToMilli(float v)
{
   return (int32_t)(v * 1000.0f);
}

static BOOL TestInputEcho(Ctx *ctx)
{
   uint32_t durationMs = ctx->durationMs ? ctx->durationMs : 30000u;
   InputView view;
   memset(&view, 0, sizeof(view));
   uint32_t lastHold = 0, changes = 0, reads = 0;
   int32_t lastLx = 0, lastLy = 0, lastRx = 0, lastRy = 0;
   uint32_t lastTouch = 0;

   LogPhase(ctx, "echo");
   MbSet(AUDIT_MB_INPUT_READS, 0);
   MbSet(AUDIT_MB_INPUT_CHANGES, 0);

   OSTime start   = OSGetTime();
   uint32_t frame = 0;
   // The host ends this test with CONTINUE when it has finished driving the pad; the duration is a backstop.
   Ctx *c = ctx;
   while (OSTicksToMilliseconds(OSGetTime() - start) < durationMs) {
      VPADStatus st;
      VPADReadError err = VPAD_READ_SUCCESS;
      int32_t n         = VPADRead(VPAD_CHAN_0, &st, 1, &err);
      MbSet(AUDIT_MB_INPUT_ERROR, (uint32_t)err);
      if (n > 0 && err == VPAD_READ_SUCCESS) {
         reads++;
         VPADTouchData cal;
         memset(&cal, 0, sizeof(cal));
         VPADGetTPCalibratedPoint(VPAD_CHAN_0, &cal, &st.tpNormal);

         view.hold    = st.hold;
         view.lx      = st.leftStick.x;
         view.ly      = st.leftStick.y;
         view.rx      = st.rightStick.x;
         view.ry      = st.rightStick.y;
         view.touched = st.tpNormal.touched != 0;
         view.tx      = (float)cal.x / 1280.0f;
         view.ty      = (float)cal.y / 720.0f;

         int32_t lx = ToMilli(st.leftStick.x), ly = ToMilli(st.leftStick.y);
         int32_t rx = ToMilli(st.rightStick.x), ry = ToMilli(st.rightStick.y);
         uint32_t touch = (view.touched ? 1u : 0u) | (st.tpNormal.validity == VPAD_VALID ? 2u : 0u);
         MbSet(AUDIT_MB_INPUT_HOLD, st.hold);
         MbSet(AUDIT_MB_INPUT_LX, (uint32_t)lx);
         MbSet(AUDIT_MB_INPUT_LY, (uint32_t)ly);
         MbSet(AUDIT_MB_INPUT_RX, (uint32_t)rx);
         MbSet(AUDIT_MB_INPUT_RY, (uint32_t)ry);
         MbSet(AUDIT_MB_TOUCH_STATE, touch);
         MbSet(AUDIT_MB_TOUCH_X, cal.x);
         MbSet(AUDIT_MB_TOUCH_Y, cal.y);
         if (st.hold != lastHold || lx != lastLx || ly != lastLy || rx != lastRx || ry != lastRy || touch != lastTouch) {
            changes++;
            lastHold  = st.hold;
            lastLx    = lx;
            lastLy    = ly;
            lastRx    = rx;
            lastRy    = ry;
            lastTouch = touch;
            MbSet(AUDIT_MB_INPUT_CHANGES, changes);
         }
         MbSet(AUDIT_MB_INPUT_READS, reads);
      }

      if (!PresentFrame(c, kBg, SceneInput, &view, frame++)) {
         return FALSE;
      }
      if (ConsumeContinue()) {
         break; // the host has finished driving the pad
      }
   }
   LogNote(ctx, "reads=%u changes=%u", (unsigned)reads, (unsigned)changes);
   Fold(ctx, reads > 0 ? 1u : 0u);
   if (reads == 0) {
      LogSelf(ctx, "fail", "VPADRead never returned a sample");
   }
   return TRUE;
}

// ---------------------------------------------------------------------------------------------

const TestEntry kAvTests[] = {
   {"audio_sweep", TestAudioSweep},
   {"input_echo", TestInputEcho},
   {NULL, NULL},
};
