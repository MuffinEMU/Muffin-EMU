// GamePad (VPAD) plus Pro Controller (KPAD) input, merged into one structure.
#include "showcase.h"

#include <padscore/kpad.h>
#include <vpad/input.h>
#include <string.h>

static u32 s_prev_hold;
static int s_prev_touch;
static int s_kpad_ok;

void input_init(void)
{
   VPADInit();
   KPADInit();
   s_kpad_ok = 1;
}

static u32 pro_to_vpad(u32 h)
{
   u32 r = 0;
   if (h & WPAD_PRO_BUTTON_A) r |= B_A;
   if (h & WPAD_PRO_BUTTON_B) r |= B_B;
   if (h & WPAD_PRO_BUTTON_X) r |= B_X;
   if (h & WPAD_PRO_BUTTON_Y) r |= B_Y;
   if (h & WPAD_PRO_BUTTON_LEFT) r |= B_LEFT;
   if (h & WPAD_PRO_BUTTON_RIGHT) r |= B_RIGHT;
   if (h & WPAD_PRO_BUTTON_UP) r |= B_UP;
   if (h & WPAD_PRO_BUTTON_DOWN) r |= B_DOWN;
   if (h & WPAD_PRO_TRIGGER_ZL) r |= B_ZL;
   if (h & WPAD_PRO_TRIGGER_ZR) r |= B_ZR;
   if (h & WPAD_PRO_TRIGGER_L) r |= B_L;
   if (h & WPAD_PRO_TRIGGER_R) r |= B_R;
   if (h & WPAD_PRO_BUTTON_PLUS) r |= B_PLUS;
   if (h & WPAD_PRO_BUTTON_MINUS) r |= B_MINUS;
   if (h & WPAD_PRO_BUTTON_STICK_L) r |= B_STICK_L;
   if (h & WPAD_PRO_BUTTON_STICK_R) r |= B_STICK_R;
   return r;
}

static float dz(float v) { return (v > -0.12f && v < 0.12f) ? 0.0f : v; }

void input_poll(Input *in)
{
   memset(in, 0, sizeof(*in));
   VPADStatus vs;
   VPADReadError err = VPAD_READ_NO_SAMPLES;
   int n = VPADRead(VPAD_CHAN_0, &vs, 1, &err);
   if (n > 0 && err == VPAD_READ_SUCCESS)
   {
      in->vpad_ok = 1;
      in->hold = vs.hold & 0x0007FFFFu;
      in->lx = dz(vs.leftStick.x);
      in->ly = dz(vs.leftStick.y);
      in->rx = dz(vs.rightStick.x);
      in->ry = dz(vs.rightStick.y);
      in->acc[0] = vs.accelerometer.acc.x;
      in->acc[1] = vs.accelerometer.acc.y;
      in->acc[2] = vs.accelerometer.acc.z;
      in->gyro[0] = vs.gyro.x; in->gyro[1] = vs.gyro.y; in->gyro[2] = vs.gyro.z;
      in->ang[0] = vs.angle.x; in->ang[1] = vs.angle.y; in->ang[2] = vs.angle.z;
      if (vs.tpNormal.touched)
      {
         // Raw touch panel units to GamePad pixels (same calibration the console uses).
         float rx = (float)vs.tpNormal.x - 92.0f;
         float ry = 4095.0f - (float)vs.tpNormal.y - 254.0f;
         if (rx < 0) rx = 0;
         if (ry < 0) ry = 0;
         in->touched = 1;
         in->tx = m_clamp(rx / 3883.0f * (float)DRC_W, 0.0f, (float)(DRC_W - 1));
         in->ty = m_clamp(ry / 3694.0f * (float)DRC_H, 0.0f, (float)(DRC_H - 1));
      }
   }

   if (s_kpad_ok)
   {
      for (int ch = 0; ch < 4; ch++)
      {
         KPADStatus ks;
         KPADError kerr = KPAD_ERROR_NO_SAMPLES;
         if (KPADReadEx((KPADChan)ch, &ks, 1, &kerr) > 0 && kerr == KPAD_ERROR_OK &&
             ks.extensionType == WPAD_EXT_PRO_CONTROLLER)
         {
            in->pro = 1;
            in->hold |= pro_to_vpad(ks.pro.hold);
            float plx = dz(ks.pro.leftStick.x), ply = dz(ks.pro.leftStick.y);
            float prx = dz(ks.pro.rightStick.x), pry = dz(ks.pro.rightStick.y);
            if (m_abs(plx) > m_abs(in->lx)) in->lx = plx;
            if (m_abs(ply) > m_abs(in->ly)) in->ly = ply;
            if (m_abs(prx) > m_abs(in->rx)) in->rx = prx;
            if (m_abs(pry) > m_abs(in->ry)) in->ry = pry;
            break;
         }
      }
   }

   in->trig = in->hold & ~s_prev_hold;
   in->touch_trig = in->touched && !s_prev_touch;
   s_prev_hold = in->hold;
   s_prev_touch = in->touched;
   in->any = (in->hold != 0) || in->touched || m_abs(in->lx) > 0.3f || m_abs(in->ly) > 0.3f ||
             m_abs(in->rx) > 0.3f || m_abs(in->ry) > 0.3f;
}

void input_rumble(int bits)
{
   static const u8 pattern[15] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                   0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
   if (bits > 120) bits = 120;
   VPADControlMotor(VPAD_CHAN_0, pattern, (uint8_t)bits);
}

void input_rumble_stop(void) { VPADStopMotor(VPAD_CHAN_0); }
