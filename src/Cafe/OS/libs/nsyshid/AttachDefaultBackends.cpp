#include "nsyshid.h"
#include "Backend.h"
#include "BackendEmulated.h"
#if !defined(CEMU_PLATFORM_IOS)
#include "BackendLibusb.h"
#endif

namespace nsyshid::backend
{
	void AttachDefaultBackends()
	{
#if !defined(CEMU_PLATFORM_IOS)
		// add libusb backend (real USB HID peripherals — not available on iOS)
		{
			auto backendLibusb = std::make_shared<backend::libusb::BackendLibusb>();
			if (backendLibusb->IsInitialisedOk())
			{
				AttachBackend(backendLibusb);
			}
		}
#endif
	   // add emulated backend
		{
			auto backendEmulated = std::make_shared<backend::emulated::BackendEmulated>();
			if (backendEmulated->IsInitialisedOk())
			{
				AttachBackend(backendEmulated);
			}
		}
	}
} // namespace nsyshid::backend
