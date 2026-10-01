#pragma once

// Loads keys.txt if it has not been read yet, or if the file or its location changed since the last read.
void KeyCache_Prepare();

// Forces the next KeyCache_Prepare() to read keys.txt again. Call after ActiveSettings::SetPaths().
// (KeyCache_Prepare() also re-reads on its own when keys.txt changes, and does not latch anything while the
// paths are still unset, so this is now only a belt for callers that already use it.)
void KeyCache_ResetForNewPaths();

// iOS: the app scans its library, inspects DLC/update files and decrypts disc images BEFORE CemuInitialize() has called
// ActiveSettings::SetPaths(), so there is no user data folder to find keys.txt in. The app names the files that will become
// keys.txt (the user-facing drop folder copy first, then the engine's copy), and KeyCache_Prepare() reads the first one that
// exists for as long as the real paths are unset. Read-only: it never creates a file from there, and once the real paths
// are set they take over (the keys are re-read from the real file the first time).
void KeyCache_SetPreInitKeyFiles(const fs::path& preferred, const fs::path& fallback);

uint8* KeyCache_GetAES128(sint32 index);

// Changes whenever the set of keys changes
uint64 KeyCache_GetFingerprint();
