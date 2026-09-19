#include "AudioBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static AudioBufferList *list(unsigned n) { AudioBufferList *p=calloc(1,sizeof(AudioBufferList)+(n-1)*sizeof(AudioBuffer)); p->mNumberBuffers=n; return p; }
int main(void) {
    float mic[]={99,99}, stereo[]={.1f,.2f,.3f,.4f}, left[2]={0},right[2]={0};
    AudioBufferList *in=list(2), *out=list(2);
    in->mBuffers[0]=(AudioBuffer){1,sizeof(mic),mic}; in->mBuffers[1]=(AudioBuffer){2,sizeof(stereo),stereo};
    out->mBuffers[0]=(AudioBuffer){1,sizeof(left),left}; out->mBuffers[1]=(AudioBuffer){1,sizeof(right),right};
    ARBridge *b=ar_create(1,1);
    ar_callback(0,0,in,0,out,0,b);
    assert(left[0]==.1f && left[1]==.3f && right[0]==.2f && right[1]==.4f);
    assert(ar_cycles(b)==1 && ar_signals(b)==1 && ar_errors(b)==0);
    out->mBuffers[1].mDataByteSize=4;
    ar_callback(0,0,in,0,out,0,b);
    assert(ar_errors(b)==1 && left[0]==0 && right[0]==0);
    // A second independent route cannot pick up the first route's buffers.
    float source2[]={.7f,.8f,.9f,1.f}, output2[4]={0};
    AudioBufferList *in2=list(1), *out2=list(1);
    in2->mBuffers[0]=(AudioBuffer){2,sizeof(source2),source2};
    out2->mBuffers[0]=(AudioBuffer){2,sizeof(output2),output2};
    ARBridge *b2=ar_create(0,1);
    ar_callback(0,0,in2,0,out2,0,b2);
    assert(output2[0]==.7f && output2[3]==1.f && ar_cycles(b2)==1);
    assert(ar_cycles(b)==1 && ar_errors(b)==1);
    source2[0]=NAN;
    ar_callback(0,0,in2,0,out2,0,b2);
    assert(output2[0]==0 && output2[1]==.8f);
    ar_set_gain(b2,.5f);
    ar_callback(0,0,in2,0,out2,0,b2); // ramp
    ar_callback(0,0,in2,0,out2,0,b2); // steady half-volume
    assert(fabsf(output2[1]-.4f)<.00001f && fabsf(output2[3]-.5f)<.00001f);
    assert(ar_cycles(b)==1); // volume changes do not touch another route
    ar_set_gain(b2,0);
    ar_callback(0,0,in2,0,out2,0,b2);
    ar_callback(0,0,in2,0,out2,0,b2);
    assert(output2[1]==0 && output2[3]==0 && ar_signals(b2)>0); // detect source even when muted
    ARBridge *muted=ar_create(0,0);
    ar_callback(0,0,in2,0,out2,0,muted);
    assert(output2[1]==0 && ar_signals(muted)==1); // initial mute has no full-volume leak
    ar_free(muted);
    ar_set_gain(b2,2); // no amplification beyond 100%
    ar_callback(0,0,in2,0,out2,0,b2);
    ar_callback(0,0,in2,0,out2,0,b2);
    assert(output2[1]==.8f && output2[3]==1.f);
    uint64_t beforeStop=ar_cycles(b2);
    ar_disable(b2);
    ar_callback(0,0,in2,0,out2,0,b2);
    assert(output2[1]==0 && ar_cycles(b2)==beforeStop);
    ar_free(b2); free(in2); free(out2);
    ar_free(b); free(in); free(out);
    puts("PASS: one-route stereo forwarding, microphone-channel exclusion, frame mismatch fails silent, independent routes, NaN sanitization, stopped route silence, per-app volume, gain ramp, initial mute, gain limits");
}
