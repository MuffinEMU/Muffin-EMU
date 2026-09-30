#include "Cafe/OS/RPL/COSModule.h"

bool mic_isActive(uint32 drcIndex);
void mic_updateOnAXFrame();

// Simulated blow into the GamePad microphone (synthetic wind noise fed to the game's mic
// buffer, no real microphone or permission involved). Thread-safe; callable from any thread.
void mic_setBlow(bool isBlowing);
bool mic_isBlowing();

namespace mic
{
	COSModule* GetModule();
};