// audit_protocol.h - the probe protocol between the guest audit program (audit.rpx) and the
// MuffinEMU Audit app. Version 1. The design and the reasoning are in docs/AUDIT.md.
//
// Two channels, each used for what it is good at:
//
//   guest -> host   OSReport lines starting "MUFFINAUDIT ". They land in the core log like every
//                   other line, in order with the core's own output, so they tag the log with the
//                   test, phase and checkpoint that was running when something else was logged.
//
//   both ways       A fixed mailbox in the guest's .bss, announced once on the log
//                   ("MUFFINAUDIT HELLO ... mailbox=0x10xxxxxx"). The host reads and writes it
//                   through the core's guest-memory hooks. The guest publishes its state there
//                   (what is running, which checkpoint it is holding, what input it saw) and the
//                   host sends commands (run this test, continue, abort) without the guest having
//                   to parse anything from a log.
//
// Everything in the mailbox is a big-endian 32-bit word (the guest's own byte order) or a
// NUL-terminated ASCII string. The host reads the offsets below; tools/audit-app/check_protocol.py
// fails CI if the Swift constants in GuestLink.swift drift from this file.
#pragma once

#include <stdint.h>

#define AUDIT_PROTOCOL_VERSION 1u
#define AUDIT_MAILBOX_MAGIC    0x4D415544u /* 'MAUD' */
#define AUDIT_MAILBOX_SIZE     0x200u

// ---- guest state values (AUDIT_MB_GUEST_STATE) -------------------------------------------------
#define AUDIT_STATE_BOOT       0u /* initialising */
#define AUDIT_STATE_IDLE       1u /* presenting an idle frame, waiting for a command */
#define AUDIT_STATE_RUNNING    2u /* a test is running */
#define AUDIT_STATE_CHECKPOINT 3u /* holding a scene still, waiting for the host to capture and continue */
#define AUDIT_STATE_FATAL      4u /* the guest cannot continue (message says why) */

// ---- host commands (AUDIT_MB_CMD) --------------------------------------------------------------
#define AUDIT_CMD_NONE     0u
#define AUDIT_CMD_RUN      1u /* run test cmdTestId with cmdParams, seed, durationMs, runToken */
#define AUDIT_CMD_CONTINUE 2u /* leave the current checkpoint */
#define AUDIT_CMD_ABORT    3u /* abandon the running test */
#define AUDIT_CMD_EXIT     4u /* leave main() */
#define AUDIT_CMD_PING     5u /* echo: the guest copies cmdSeq into pingEcho */

// ---- test result (AUDIT_MB_TEST_RESULT) --------------------------------------------------------
#define AUDIT_RESULT_NONE    0u
#define AUDIT_RESULT_OK      1u /* ran to the end; says nothing about what it drew */
#define AUDIT_RESULT_ERROR   2u /* the guest saw an error itself (see message) */
#define AUDIT_RESULT_ABORTED 3u
#define AUDIT_RESULT_UNKNOWN 4u /* no such test in this build */

// ---- mailbox layout: byte offsets from the announced address -----------------------------------
// guest -> host
#define AUDIT_MB_MAGIC            0x000u /* u32 AUDIT_MAILBOX_MAGIC, written last during init */
#define AUDIT_MB_VERSION          0x004u /* u32 AUDIT_PROTOCOL_VERSION */
#define AUDIT_MB_GUEST_STATE      0x008u /* u32 AUDIT_STATE_* */
#define AUDIT_MB_GUEST_SEQ        0x00Cu /* u32 bumped on every state change, checkpoint and test start/end */
#define AUDIT_MB_FRAMES           0x010u /* u32 frames the guest has presented since boot */
#define AUDIT_MB_RUN_TOKEN        0x014u /* u32 runToken of the current or last test */
#define AUDIT_MB_CHECKPOINT_SEQ   0x018u /* u32 bumped each time a checkpoint is reached */
#define AUDIT_MB_TEST_RESULT      0x01Cu /* u32 AUDIT_RESULT_* of the last finished test */
#define AUDIT_MB_CHECKSUM         0x020u /* u32 guest-computed digest of what the last test did (same on every correct core) */
#define AUDIT_MB_GUEST_ERRORS     0x024u /* u32 count of error returns the guest noticed in this test */
#define AUDIT_MB_PING_ECHO        0x028u /* u32 last PING cmdSeq seen */
#define AUDIT_MB_ACK_SEQ          0x02Cu /* u32 last host cmdSeq the guest consumed */
#define AUDIT_MB_INPUT_HOLD       0x030u /* u32 VPAD hold bitmask of the last read */
#define AUDIT_MB_INPUT_LX         0x034u /* s32 left stick x * 1000 */
#define AUDIT_MB_INPUT_LY         0x038u /* s32 left stick y * 1000 (up positive) */
#define AUDIT_MB_INPUT_RX         0x03Cu /* s32 right stick x * 1000 */
#define AUDIT_MB_INPUT_RY         0x040u /* s32 right stick y * 1000 */
#define AUDIT_MB_TOUCH_STATE      0x044u /* u32 bit0 touched, bit1 touch data valid */
#define AUDIT_MB_TOUCH_X          0x048u /* u32 calibrated touch x, 0..1279 */
#define AUDIT_MB_TOUCH_Y          0x04Cu /* u32 calibrated touch y, 0..719 */
#define AUDIT_MB_INPUT_READS      0x050u /* u32 VPADRead calls that returned a sample */
#define AUDIT_MB_INPUT_CHANGES    0x054u /* u32 bumped whenever hold, sticks or touch changed */
#define AUDIT_MB_INPUT_ERROR      0x058u /* u32 last VPADReadError */
#define AUDIT_MB_AUDIO_STATE      0x05Cu /* u32 0 none, 1 voice playing, 2 finished */
#define AUDIT_MB_AUDIO_STEP       0x060u /* u32 sweep step the guest is on */
#define AUDIT_MB_CHECKPOINT_NAME  0x080u /* char[48] */
#define AUDIT_MB_TEST_ID          0x0B0u /* char[48] current test id */
#define AUDIT_MB_MESSAGE          0x0E0u /* char[96] last guest message */
// host -> guest
#define AUDIT_MB_CMD              0x100u /* u32 AUDIT_CMD_*; written BEFORE cmdSeq */
#define AUDIT_MB_CMD_SEQ          0x104u /* u32 host increments last; the guest acts when it differs from ACK_SEQ */
#define AUDIT_MB_CMD_RUN_TOKEN    0x108u /* u32 */
#define AUDIT_MB_CMD_DURATION_MS  0x10Cu /* u32 0 = the test's own default */
#define AUDIT_MB_CMD_SEED         0x110u /* u32 */
#define AUDIT_MB_HOST_FLAGS       0x114u /* u32 bit0 capture armed and working, bit1 pad surface present */
#define AUDIT_MB_CMD_TEST_ID      0x120u /* char[48] */
#define AUDIT_MB_CMD_PARAMS       0x150u /* char[128] "key=value;key=value" */

#define AUDIT_NAME_LEN    48u
#define AUDIT_MESSAGE_LEN 96u
#define AUDIT_PARAMS_LEN  128u

// ---- log markers (OSReport) --------------------------------------------------------------------
// All of them start with AUDIT_LOG_PREFIX. Fields are space separated; free text is last.
//   MUFFINAUDIT HELLO <protocol> <build> mailbox=0x<addr> tv=<w>x<h>
//   MUFFINAUDIT TEST_BEGIN <id> <token> seed=<n> <params>
//   MUFFINAUDIT PHASE <id> <token> <name>
//   MUFFINAUDIT CHECKPOINT <id> <token> <name> frame=<n>
//   MUFFINAUDIT NOTE <id> <token> <free text>
//   MUFFINAUDIT SELF <id> <token> <pass|fail|info> <free text>
//   MUFFINAUDIT TEST_END <id> <token> <ok|error|aborted> checksum=<hex> frames=<n> errors=<n>
//   MUFFINAUDIT BYE
#define AUDIT_LOG_PREFIX "MUFFINAUDIT"
