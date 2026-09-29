#pragma once

void KeyCache_Prepare();

// Re-arms KeyCache_Prepare()'s one-shot latch. Call after ActiveSettings::SetPaths() so keys.txt is
// re-read from the real path if an earlier call ran before the paths were set.
void KeyCache_ResetForNewPaths();

uint8* KeyCache_GetAES128(sint32 index);