#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
typedef struct ARBridge ARBridge;
ARBridge *ar_create(uint32_t inputOffset, float initialGain);
void ar_set_gain(ARBridge *bridge, float gain);
void ar_disable(ARBridge *bridge);
void ar_free(ARBridge *bridge);
uint64_t ar_cycles(ARBridge *bridge);
uint64_t ar_signals(ARBridge *bridge);
uint64_t ar_errors(ARBridge *bridge);
OSStatus ar_callback(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *, const AudioTimeStamp *, AudioBufferList *, const AudioTimeStamp *, void *);
OSStatus ar_tap_input_only(AudioObjectID device, AudioDeviceIOProcID io, uint32_t streams);
OSStatus ar_install(AudioObjectID device, ARBridge *bridge, AudioDeviceIOProcID *io);
int ar_parent(int pid);
int ar_path(int pid, char *buffer, uint32_t size);
