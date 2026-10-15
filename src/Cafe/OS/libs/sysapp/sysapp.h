#include "Cafe/OS/RPL/COSModule.h"

namespace sysapp
{
	COSModule* GetModule();
}

uint64 _SYSGetSystemApplicationTitleId(sint32 index);
// true for any region of a system application (Account Settings, System Settings, Mii Maker...)
bool _SYSIsSystemApplicationTitleId(uint64 titleId);