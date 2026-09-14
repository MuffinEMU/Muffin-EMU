//
//  iOSAudioInputAPI.mm
//  cemuMain
//
//  Created by Codex on 7/15/2026.
//

#include <TargetConditionals.h>

#if defined(__APPLE__) && TARGET_OS_IOS

#include "iOSAudioInputAPI.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#import <AVFoundation/AVFoundation.h>

IOSAudioInputAPI::IOSAudioInputAPI(uint32 samplerate,
                                   uint32 channels,
                                   uint32 samples_per_block,
                                   uint32 bits_per_sample)
	: IAudioInputAPI(samplerate, channels, samples_per_block, bits_per_sample),
	  m_buffer((size_t)samples_per_block * channels * (bits_per_sample / 8) * kBlockCount)
{
    NSError* error = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    
    if (session.recordPermission == AVAudioSessionRecordPermissionDenied)
        throw std::runtime_error("microphone permission was denied");
    
    if (session.recordPermission == AVAudioSessionRecordPermissionUndetermined)
        [session requestRecordPermission:^(BOOL granted) {}];
    
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker
                   error:&error];
    [session setPreferredSampleRate:samplerate error:&error];
    [session setPreferredIOBufferDuration:(double)samples_per_block / samplerate error:&error];
    [session setActive:YES error:&error];
    
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp || AudioComponentInstanceNew(comp, &m_audioUnit) != noErr)
        throw std::runtime_error("can't initialize iOS microphone audio unit");
    
    auto disposeAudioUnitOnError = [this]() {
        AudioComponentInstanceDispose(m_audioUnit);
        m_audioUnit = nullptr;
    };
    
    UInt32 enableInput = 1;
    if (AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1, &enableInput, sizeof(enableInput)) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't enable iOS microphone input");
    }
    
    const uint32 bytesPerSample = bits_per_sample / 8;
    
    AudioStreamBasicDescription format{};
    format.mSampleRate       = samplerate;
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = m_channels;
    format.mBitsPerChannel   = bits_per_sample;
    format.mFramesPerPacket  = 1;
    format.mBytesPerFrame    = m_channels * bytesPerSample;
    format.mBytesPerPacket   = format.mBytesPerFrame * format.mFramesPerPacket;
    
    if (AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 1, &format, sizeof(format)) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't set iOS microphone stream format");
    }
    
    AURenderCallbackStruct callback{};
    callback.inputProc = InputCallback;
    callback.inputProcRefCon = this;
    
    if (AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global, 1, &callback, sizeof(callback)) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't set iOS microphone callback");
    }
    
    const auto sessionFrames = static_cast<size_t>(std::ceil(session.sampleRate * session.IOBufferDuration));
    const auto captureFrames = std::max<size_t>(samples_per_block, sessionFrames) + 1;
    m_captureBuffer.resize(captureFrames * m_channels * (bits_per_sample / 8));
    
    if (AudioUnitInitialize(m_audioUnit) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't initialize iOS microphone audio unit");
    }
}

IOSAudioInputAPI::~IOSAudioInputAPI()
{
    if (m_audioUnit) {
        m_isPlaying = false;
        AudioOutputUnitStop(m_audioUnit);
        AudioUnitUninitialize(m_audioUnit);
        AudioComponentInstanceDispose(m_audioUnit);
        m_audioUnit = nullptr;
    }
}

bool IOSAudioInputAPI::ConsumeBlock(sint16* data)
{
    const auto copied = m_buffer.read(reinterpret_cast<std::uint8_t*>(data), m_bytesPerBlock);
    if (copied != m_bytesPerBlock)
        std::memset(reinterpret_cast<std::uint8_t*>(data) + copied, 0, m_bytesPerBlock - copied);
    
    return true;
}

bool IOSAudioInputAPI::Play()
{
    if (!m_audioUnit)
        return false;
    if (m_isPlaying)
        return true;
    
    if (AudioOutputUnitStart(m_audioUnit) != noErr)
        return false;
    
    m_isPlaying = true;
    return true;
}

bool IOSAudioInputAPI::Stop()
{
    if (!m_audioUnit)
        return false;
    if (!m_isPlaying)
        return true;
    
    if (AudioOutputUnitStop(m_audioUnit) != noErr)
        return false;
    
    m_isPlaying = false;
    return true;
}

OSStatus IOSAudioInputAPI::InputCallback(void* inRefCon,
                                         AudioUnitRenderActionFlags* ioActionFlags,
                                         const AudioTimeStamp* inTimeStamp,
                                         UInt32 inBusNumber,
                                         UInt32 inNumberFrames,
                                         AudioBufferList* ioData)
{
    auto* self = reinterpret_cast<IOSAudioInputAPI*>(inRefCon);
    if (!self || !self->m_audioUnit)
        return noErr;
    
    const auto bytesNeeded = (size_t)inNumberFrames * self->m_channels * (self->m_bitsPerSample / 8);
    if (bytesNeeded > self->m_captureBuffer.size())
        return noErr;
    
    AudioBufferList bufferList{};
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = self->m_channels;
    bufferList.mBuffers[0].mDataByteSize = static_cast<UInt32>(bytesNeeded);
    bufferList.mBuffers[0].mData = self->m_captureBuffer.data();
    
    OSStatus status = AudioUnitRender(self->m_audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
    if (status != noErr)
        return status;
    
    self->m_buffer.write(self->m_captureBuffer.data(), bytesNeeded);
    return noErr;
}

std::vector<IAudioInputAPI::DeviceDescriptionPtr> IOSAudioInputAPI::GetDevices()
{
    std::vector<DeviceDescriptionPtr> devices;
    devices.push_back(std::make_shared<IOSAudioInputDeviceDescription>());
    return devices;
}

#endif
