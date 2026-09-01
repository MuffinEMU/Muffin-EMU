#pragma once

void KeyCache_Prepare();

// Forget every cached key and re-read keys.txt.
//
// KeyCache_Prepare() is deliberately one-shot, which is correct on desktop: keys.txt
// sits next to the executable and is edited before Cemu is started. On iOS the file is
// imported through the Files app while the app is already running, so without a way to
// re-read it a key imported after anything had already touched the FST layer would not
// take effect until the process was killed and relaunched - and until then the user
// would be told their own, correct key was missing.
void KeyCache_Reload();

uint8* KeyCache_GetAES128(sint32 index);