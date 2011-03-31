// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

// These coefficients are scaled to allow headroom in the result.
// They are in 4q28 format.

#define s1_NUM_COEFF 38
#define s1_UPSAMPLING_RATE 2

int s1FirCoeff[s1_NUM_COEFF] = {
    0x000c2931 ,
    0x001645a6 ,
    0xfffdb21c ,
    0xffdbb2dc ,
    0xfffcf526 ,
    0x003e5240 ,
    0x00101ec4 ,
    0xff9c855f ,
    0xffd784d2 ,
    0x0097399f ,
    0x00527091 ,
    0xff1f071b ,
    0xff650256 ,
    0x0153295a ,
    0x01243600 ,
    0xfdd30235 ,
    0xfd839a56 ,
    0x05056396 ,
    0x0e175bfb ,
    0x0e175bfb ,
    0x05056396 ,
    0xfd839a56 ,
    0xfdd30235 ,
    0x01243600 ,
    0x0153295a ,
    0xff650256 ,
    0xff1f071b ,
    0x00527091 ,
    0x0097399f ,
    0xffd784d2 ,
    0xff9c855f ,
    0x00101ec4 ,
    0x003e5240 ,
    0xfffcf526 ,
    0xffdbb2dc ,
    0xfffdb21c ,
    0x001645a6 ,
    0x000c2931
};


// With inputs in the range [-1,+1], the maximum output with these coefficients is:
//        3.7234471498853896e+00
//
// Note that this not scaled, so 1.0 corresponds to 1q31
// Note also that both the positive and negative values can occur

