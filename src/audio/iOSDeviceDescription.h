//
//  iOSDeviceDesciption.mm
//  cemuMain
//
//  Created by Stossy11 on 5/3/2026.
//

#pragma once

#include "IAudioAPI.h"
#include <AudioUnit/AudioUnit.h>
#include <mutex>
#include <queue>
#include <vector>

class IOSDeviceDescription final : public IAudioAPI::DeviceDescription
{
public:
    IOSDeviceDescription()
        : DeviceDescription(L"iOS Default Output") {}

    std::wstring GetIdentifier() const override
    {
        return L"default";
    }
};
