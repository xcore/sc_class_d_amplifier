// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef GLOBAL_H_
#define GLOBAL_H_

// Global settings and configuration variables

#ifdef RELEASE
#define USE_STREAMING_CHANNELS
#undef VERBOSE
#else
#undef USE_STREAMING_CHANNELS
#define VERBOSE
#endif

// ------------------------------------------------------------------------------------------------------------
#ifdef __XC__
#ifdef USE_STREAMING_CHANNELS
#define streaming_chanend streaming chanend
#else
#define streaming_chanend chanend
#endif
#else
#define streaming_chanend unsigned
#endif

#endif /*GLOBAL_H_*/
