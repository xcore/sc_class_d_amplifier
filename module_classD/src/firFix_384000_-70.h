// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

// These coefficients are scaled to allow headroom in the result.
// They are in 4q28 format.

#define s2_NUM_COEFF 22
#define s2_UPSAMPLING_RATE 4

int s2FirCoeff[s2_NUM_COEFF] = {
    0x000a328e ,
    0x00002ae5 ,
    0xffc2d2f4 ,
    0xff4012cd ,
    0xfeaf8a75 ,
    0xfea7d024 ,
    0xffe80a67 ,
    0x02da1bc1 ,
    0x07197127 ,
    0x0b62b681 ,
    0x0e17c9f5 ,
    0x0e17c9f5 ,
    0x0b62b681 ,
    0x07197127 ,
    0x02da1bc1 ,
    0xffe80a67 ,
    0xfea7d024 ,
    0xfeaf8a75 ,
    0xff4012cd ,
    0xffc2d2f4 ,
    0x00002ae5 ,
    0x000a328e
};


// With inputs in the range [-1,+1], the maximum output with these coefficients is:
//        4.9014283351312589e+00
//
// Note that this not scaled, so 1.0 corresponds to 1q31
// Note also that both the positive and negative values can occur

