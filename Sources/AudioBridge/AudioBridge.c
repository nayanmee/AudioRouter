#include "AudioBridge.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libproc.h>
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio gain requires lock-free integer atomics");
struct ARBridge { uint32_t offset; _Atomic uint32_t gainMilli; float currentGain; _Atomic uint64_t cycles, signals, errors; _Atomic int disabled; };
static uint32_t gain_value(float gain) { return !isfinite(gain) ? 0 : (uint32_t)lroundf(fminf(1.f,fmaxf(0.f,gain))*1000.f); }
ARBridge *ar_create(uint32_t offset, float initialGain) {
    ARBridge *p = calloc(1, sizeof(*p));
    if(p) { p->offset = offset; atomic_init(&p->gainMilli,gain_value(initialGain)); p->currentGain=atomic_load(&p->gainMilli)/1000.f; }
    return p;
}
void ar_set_gain(ARBridge *p, float gain) { atomic_store_explicit(&p->gainMilli,gain_value(gain),memory_order_relaxed); }
void ar_disable(ARBridge *p) { atomic_store(&p->disabled,1); }
void ar_free(ARBridge *p) { free(p); }
uint64_t ar_cycles(ARBridge *p) { return atomic_load_explicit(&p->cycles, memory_order_relaxed); }
uint64_t ar_signals(ARBridge *p) { return atomic_load_explicit(&p->signals, memory_order_relaxed); }
uint64_t ar_errors(ARBridge *p) { return atomic_load_explicit(&p->errors, memory_order_relaxed); }
// No allocation, locks, dispatch, Objective-C, or logging on the audio thread.
static const AudioBuffer *channel(const AudioBufferList *list, uint32_t index, uint32_t *within) {
    if (!list) return NULL;
    for (uint32_t b=0;b<list->mNumberBuffers;b++) {
        const AudioBuffer *buf=&list->mBuffers[b];
        if (index<buf->mNumberChannels) { *within=index; return buf; }
        index-=buf->mNumberChannels;
    } return NULL;
}
OSStatus ar_callback(AudioObjectID dev, const AudioTimeStamp *now, const AudioBufferList *in, const AudioTimeStamp *it, AudioBufferList *out, const AudioTimeStamp *ot, void *context) {
    ARBridge *p=context;
    if(out) for(uint32_t b=0;b<out->mNumberBuffers;b++) if(out->mBuffers[b].mData) memset(out->mBuffers[b].mData,0,out->mBuffers[b].mDataByteSize);
    if(atomic_load(&p->disabled)) return noErr;
    const AudioBuffer *src[2], *dst[2]; uint32_t si[2],di[2],frames=0;
    for(uint32_t c=0;c<2;c++) {
        src[c]=channel(in,p->offset+c,&si[c]); dst[c]=channel(out,c,&di[c]);
        if(!src[c] || !dst[c] || !src[c]->mData || !dst[c]->mData || !src[c]->mNumberChannels || !dst[c]->mNumberChannels) goto bad;
        uint32_t n=src[c]->mDataByteSize/(sizeof(float)*src[c]->mNumberChannels);
        uint32_t m=dst[c]->mDataByteSize/(sizeof(float)*dst[c]->mNumberChannels);
        if(!n || n!=m || (c && n!=frames)) goto bad;
        frames=n;
    }
    int signal=0;
    float targetGain=atomic_load_explicit(&p->gainMilli,memory_order_relaxed)/1000.f;
    float initialGain=p->currentGain;
    // One-buffer linear ramp; both stereo channels share exactly the same gain.
    for(uint32_t f=0;f<frames;f++) for(uint32_t c=0;c<2;c++) {
        float v=((float*)src[c]->mData)[f*src[c]->mNumberChannels+si[c]];
        if(!isfinite(v)) v=0;
        if(fabsf(v)>0.00001f) signal=1;
        ((float*)dst[c]->mData)[f*dst[c]->mNumberChannels+di[c]]=v*(initialGain+(targetGain-initialGain)*(float)(f+1)/(float)frames);
    }
    p->currentGain=targetGain;
    atomic_fetch_add_explicit(&p->cycles,1,memory_order_relaxed);
    if(signal) atomic_fetch_add_explicit(&p->signals,1,memory_order_relaxed);
    return noErr;
bad:
    atomic_fetch_add_explicit(&p->errors,1,memory_order_relaxed);
    return noErr;
}
int ar_parent(int pid) { struct proc_bsdinfo info={0}; return proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))==sizeof(info) ? (int)info.pbi_ppid : 0; }
int ar_path(int pid,char *buffer,uint32_t size) { return proc_pidpath(pid,buffer,size); }

OSStatus ar_install(AudioObjectID device, ARBridge *bridge, AudioDeviceIOProcID *io) { return AudioDeviceCreateIOProcID(device, ar_callback, bridge, io); }

OSStatus ar_tap_input_only(AudioObjectID device, AudioDeviceIOProcID io, uint32_t streams) {
    if(streams<=1) return noErr;
    UInt32 size=(UInt32)(sizeof(AudioHardwareIOProcStreamUsage)+(streams-1)*sizeof(UInt32));
    AudioHardwareIOProcStreamUsage *usage=calloc(1,size);
    if(!usage) return kAudioHardwareUnspecifiedError;
    usage->mIOProc=(void*)io; usage->mNumberStreams=streams;
    usage->mStreamIsOn[streams-1]=1;
    AudioObjectPropertyAddress a={kAudioDevicePropertyIOProcStreamUsage,kAudioObjectPropertyScopeInput,kAudioObjectPropertyElementMain};
    OSStatus status=AudioObjectSetPropertyData(device,&a,0,NULL,size,usage);
    free(usage); return status;
}
