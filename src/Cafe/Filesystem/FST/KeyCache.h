#pragma once

void KeyCache_Prepare();

// Re-arms KeyCache_Prepare()'s one-shot latch. On iOS the library screen can construct a
// TitleInfo (and so call KeyCache_Prepare()) for an already-imported .wud/.wux/NUS dump
// before ActiveSettings::SetPaths() has ever run, which permanently latches the cache
// against a keys.txt that does not exist yet. Call this once, right after SetPaths(),
// so the next KeyCache_Prepare() call re-reads keys.txt from the real path.
void KeyCache_ResetForNewPaths();

uint8* KeyCache_GetAES128(sint32 index);