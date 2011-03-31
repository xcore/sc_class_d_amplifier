// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifdef CLASSD_OUTPUT

// Use c routines to bypass thread disjointedness rules

#include "pwmDefines.h"
#include <print.h>

// samples are written to from one thread, and read from another (this one)
int fifoRead (int fifoBasePtr, int fifoPtrPtr, int fifoCheckBasePtr, int fifoCheckVal) {
  int *fifoBase;
  int *fifoPtr;
  int readData;
  int *fifoCheckBase;
  int readCheckData;

  fifoBase = (int *)(fifoBasePtr);
  fifoPtr  = (int *)(fifoPtrPtr);
  fifoCheckBase = (int *)(fifoCheckBasePtr);

  // Check the sample number
  readCheckData = fifoCheckBase[*fifoPtr];
  #if PRINT == PWM_FLOW_CHECK
    if (readCheckData != fifoCheckVal)
    {
      printstrln("PWM Fifo Checking failure");
      printstr("Expected: ");
      printintln(fifoCheckVal);
      printstr("Actual:   ");
      printintln(readCheckData);
      while(1);
    }
  #endif

  // now perform read
  readData = fifoBase[*fifoPtr];
  (*fifoPtr)++;
  (*fifoPtr) = (*fifoPtr) & PWM_FIFO_MASK;
  return (readData);

}

// Read the sample rate attributes (written by another thread).
extern int attribute [NUM_ATTR_ELEMS];

int attr (int element)
{
  return (attribute [ element]);
}

#endif

