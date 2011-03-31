// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef AUDIOMANAGER_H_
#define AUDIOMANAGER_H_

// class D output
// Structure for pwm port pins
typedef struct
{
  out port hiFetGateL;
  out port loFetGateL;
  out port hiFetGateR;
  out port loFetGateR;
} s_audio;

#endif /*AUDIOMANAGER_H_*/
