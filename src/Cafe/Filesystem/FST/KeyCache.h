#pragma once

// Loads keys.txt if it has not been read yet, or if the file or its location changed since the last read.
void KeyCache_Prepare();

// Forces the next KeyCache_Prepare() to read keys.txt again. Call after ActiveSettings::SetPaths().
// (KeyCache_Prepare() also re-reads on its own when keys.txt changes, and does not latch anything while the
// paths are still unset, so this is now only a belt for callers that already use it.)
void KeyCache_ResetForNewPaths();

uint8* KeyCache_GetAES128(sint32 index);

// Changes whenever the set of keys changes
uint64 KeyCache_GetFingerprint();
