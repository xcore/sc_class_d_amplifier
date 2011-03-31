// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/**
 * @file audio.xc
 * @brief iPod Dock classD power amp
 * @author Anthony Wood, XMOS Semiconductor Ltd
 * @version 0.1
 **/
#ifdef CLASSD_OUTPUT

#include <syscall.h>
#include <platform.h>
#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include "pwmDefines.h"

#if SAMPLE_SOURCE != USB
  extern int sineWave1000[1000];
#endif



////////////////////////////////////////////////////////////////////////////////
#include "firFix_96000_-70.h" // defines coefficient values

// The number of samples required to interpolate using that filter
//#define s1_SAMPLE_TABLE_SIZE  ((int)(floor (s1_NUM_COEFF/s1_UPSAMPLING_RATE + s1_UPSAMPLING_RATE-1)))
#define s1_SAMPLE_TABLE_SIZE  20

#include "firFix_384000_-70.h" // defines coefficient values

// The number of samples required to interpolate using that filter
//#define s2_SAMPLE_TABLE_SIZE  ((int)(floor (s2_NUM_COEFF/s2_UPSAMPLING_RATE + s2_UPSAMPLING_RATE-1)))
#define s2_SAMPLE_TABLE_SIZE  8 // Using the equation above which doesn't seem to work

// Since the USB_SAMPLE_BUFFER is used to store the old samples to perform the interpolation filtering on
// Overflow occurs before the buffer is actually full.
#define USB_SAMPLE_BUFFER_OVERFLOW (USB_SAMPLE_BUFFER_SIZE - s1_NUM_COEFF)

//////////////////////////////////////////////////////////////////

void interpolate (int s1InputSamples [USB_SAMPLE_BUFFER_SIZE],
                  int s1SampleHeadPtr,
                  int s2InputSamples [s2_SAMPLE_TABLE_SIZE],
                  int &s2SampleHeadPtr,
                  #if SAMPLE_SOURCE == SINE_PWM_FIFO_WR
                    int &sampleNo, // Used to index sine table
                  #endif
                  int pwmSampleFifo[PWM_FIFO_SIZE],
                  int pwmSampleFifoCheck[PWM_FIFO_SIZE],
                  unsigned int &pwmFifoCheckVal,
                  int &pwmSampleFifoPtr                    // by ref: Fifo read ptr incremented within function
                  )
{
  for (int s1interpolationSampleNo = 0; s1interpolationSampleNo < s1_UPSAMPLING_RATE ; s1interpolationSampleNo++) {

    // First active (non-zero) sample
    int    sampleIndex = s1SampleHeadPtr;
    int    coeffNo;
    // filterSum[63:0] is split into Hi and Lo words.
    // filterSum is 5q59 = 4q28 (coeff) * 1q31 (sample)
    int           filterSumHi = 0; // [63:32] of the filter sum
    unsigned int  filterSumLo = 0; // [31: 0] of the filter sum

    int    interpolatedSample;     // 5q27 (scaled from interpolationSample)

    // Interpolating filter inserts extra 0s as extra samples.
    // This is the same as not adding those taps in.
    // So the 48000 taps are swept across the coefficients missing many of them

    // Increase the speed of the inner loop by avoiding the array range checks
    #pragma unsafe arrays
    for (coeffNo = s1interpolationSampleNo; coeffNo < s1_NUM_COEFF; coeffNo += s1_UPSAMPLING_RATE) {
      // Perform MAC for the tap.
      {filterSumHi, filterSumLo} = macs(s1FirCoeff[coeffNo], s1InputSamples[sampleIndex], filterSumHi, filterSumLo);
      if (sampleIndex == 0 ) {
          sampleIndex = USB_SAMPLE_BUFFER_SIZE-1;
      } else {
          sampleIndex --;
      }
    }

///////////////////////////////////////////////
    // Stage2 Filter
    {
      int s2interpolationSampleNo;

      if (s2SampleHeadPtr == (s2_SAMPLE_TABLE_SIZE-1)) {
        s2SampleHeadPtr = 0;
      } else {
        s2SampleHeadPtr ++;
      }


      // Get new 192000 sample
      s2InputSamples[s2SampleHeadPtr] = filterSumHi;  // 5q27

      for (s2interpolationSampleNo = 0; s2interpolationSampleNo < s2_UPSAMPLING_RATE ; s2interpolationSampleNo++) {

        // First active (non-zero) sample
        int    sampleIndex = s2SampleHeadPtr;
        int    coeffNo;
        // filterSum[63:0] is split into Hi and Lo words.
        // filterSum is 9q55 = 4q28 (coeff) * 5q27 (sample)
        int           filterSumHi = 0; // [63:32] of the filter sum
        unsigned int  filterSumLo = 0; // [31: 0] of the filter sum

        int    interpolatedSample;     // 5q27 (scaled from interpolationSample)

        // Interpolating filter inserts extra 0s as extra samples.
        // This is the same as not adding those taps in.
        // So the 192000 taps are swept across the coefficients missing many of them

        // Increase the speed of the inner loop by avoiding the array range checks
        #pragma unsafe arrays
        for (coeffNo = s2interpolationSampleNo; coeffNo < s2_NUM_COEFF; coeffNo += s2_UPSAMPLING_RATE) {
          // Perform MAC for the tap.
          {filterSumHi, filterSumLo} = macs(s2FirCoeff[coeffNo], s2InputSamples[sampleIndex], filterSumHi, filterSumLo);
          if (sampleIndex == 0 ) {
              sampleIndex = s2_SAMPLE_TABLE_SIZE-1;
          } else {
              sampleIndex --;
          }
        }

        // filterSum is 9q55
        // lose headroom & issue sample in 1q31 format
        interpolatedSample = (filterSumHi << 8) + (filterSumLo >> 24);

        #if SAMPLE_SOURCE == SINE_PWM_FIFO_WR
          // Inject a sine wave into the PWM fifo
          pwmSampleFifo[pwmSampleFifoPtr] = sineWave1000[sampleNo];
          sampleNo+=SAMPLE_INC;
          if (sampleNo >= 1000)
          {
            sampleNo -= 1000;
          }
        #else
          // This is the interpolated sample for output
          pwmSampleFifo[pwmSampleFifoPtr] = interpolatedSample;
        #endif

        pwmSampleFifoCheck[pwmSampleFifoPtr] = pwmFifoCheckVal++;
        pwmSampleFifoPtr++;
        pwmSampleFifoPtr &= PWM_FIFO_MASK;

      } // stage2 filter loop
    } // stage2 filter
  } // stage1 filter loop
}

////////////////////////////////////////////////////////////////////////////////

void audioDac( streaming chanend c_dac,
               streaming chanend c_pwmCntl,
               int pwmSampleFifo[PWM_FIFO_SIZE],
               int pwmSampleFifoCheck[PWM_FIFO_SIZE],
               int left,
               out port ?testPort) // ? means it may be null
{

  // Raw sample buffer
  // Samples from USB are written into this
  // Interpolation is performed on this buffer, so even when samples have been read
  // They still need to be valid for a while since the filter still operates on them.
  int UsbSample [USB_SAMPLE_BUFFER_SIZE]; // 1q31 48000
  int UsbSampleCheck [USB_SAMPLE_BUFFER_SIZE]; // 0++
  int UsbSampleWrPtr;
  int UsbSampleRdPtr;
  int UsbSampleCount;

  int s2InputSamples [s2_SAMPLE_TABLE_SIZE]; // 5q27 96000
  int s2SampleHeadPtr; // Points to the location which has the latest sample in it

  int pwmSampleFifoPtr; // points to the next location to write to

  unsigned int nextSample;
  unsigned int pwmCntl=0xba;

  // Count the number of samples actually provided per 32768 samples
  // Adjust the sample rate according to the change in buffer size in that time.
  unsigned int pwmFifoCheckVal;  //
  int UsbSampleWr;
  int UsbSampleRd=0;

  int active = FALSE;  // Currently receiveing samples and outputing PWM

  #if ((SAMPLE_SOURCE == SINE_PWM_FIFO_WR) || (SAMPLE_SOURCE == SINE_USB_FIFO_WR))
    int sampleNo = 0;
  #endif

  // Send location of pwmSampleFifo to pwm thread
  {
    unsigned fifoAddr;
    CAST32(fifoAddr, pwmSampleFifo);
    c_pwmCntl <: fifoAddr;
    CAST32(fifoAddr, pwmSampleFifoCheck);
    c_pwmCntl <: fifoAddr;
  }

  while (1)
  {
    // Repeat this loop for rate changes etc.

    // Start with the buffer empty
    UsbSampleWr = 0;
    UsbSampleRdPtr = 0;
    UsbSampleWrPtr = 0;
    UsbSampleCount = 0;
    UsbSampleRd = 0;

    // Ensure stage 2 buffer is fully cleared of samples
    for (s2SampleHeadPtr = 0; s2SampleHeadPtr < s2_SAMPLE_TABLE_SIZE; s2SampleHeadPtr++)
    {
      s2InputSamples[s2SampleHeadPtr] = 0;
    }
    s2SampleHeadPtr = 0;

    // Init PWM buffer & checker
    // leave half full of 0s
    for (pwmSampleFifoPtr = 0; pwmSampleFifoPtr < PWM_FIFO_SIZE; pwmSampleFifoPtr++)
    {
      pwmSampleFifo[pwmSampleFifoPtr]=0;
    }
    for (pwmFifoCheckVal = 0; pwmFifoCheckVal < PWM_FIFO_INIT; pwmFifoCheckVal++)
    {
      pwmSampleFifoCheck[pwmFifoCheckVal]=pwmFifoCheckVal;
    }
    pwmSampleFifoPtr  = PWM_FIFO_INIT;
    pwmFifoCheckVal   = PWM_FIFO_INIT;

    // Accept input samples, but do not process yet.
    active = FALSE;

    while (active != RESET)
    {
      // Keep within this loop whilst receiving samples, interpolating them and outputting them
      // For rate changes leave this loop and reset the buffers.
      select
      {
        ////////////////////////////////
        // Next sample from USB ready
        case c_dac :> nextSample:
        {
          #if DEBUG == RX_SAMPLE
          if ((active == TRUE) && (left == 0))
          {
            testPort <: 1;
          }
          #endif
          // When the samples start, fill the buffer with samples before starting the PWM
          if (
               (active == FALSE) &&
               (UsbSampleCount > USB_SAMPLE_BUFFER_INIT)
             )
          {
            // Tell the PWM thread to start operation
            c_pwmCntl <: PWM_CNTL_START_PWM;

            // We are have started PWM operation
            active = TRUE;
          }

          if (nextSample == DUMMY_SAMPLE_STOP)
          {
            // Stop the pwm thread
            c_pwmCntl <: PWM_CNTL_STOP_PWM;
            active = RESET;
          }

          // Save sample, incr pointer & wrap if necc.
          #if SAMPLE_SOURCE == SINE_USB_FIFO_WR
            // Inject a sine wave into the PWM fifo
            UsbSample[UsbSampleWrPtr] = sineWave1000[sampleNo];
            sampleNo+=SAMPLE_INC;
            if (sampleNo >= 1000)
            {
              sampleNo -= 1000;
            }
          #else
            UsbSample[UsbSampleWrPtr] = nextSample;
          #endif
          UsbSampleCheck[UsbSampleWrPtr] = UsbSampleWr;

          UsbSampleWrPtr++;
          UsbSampleWrPtr &= USB_SAMPLE_BUFFER_PTR_MASK;
          UsbSampleWr++;
          UsbSampleCount++;

          #if DEBUG == BUFFER_LEVEL
            // If buffer getting too full slow down the sample receive rate
            if (UsbSampleCount >= USB_SAMPLE_BUFFER_INIT+20)
            {
              testPort <: 1;
            }
          #endif

          #if PRINT == USB_FLOW_CHECK
            if (UsbSampleCount > USB_SAMPLE_BUFFER_OVERFLOW)
            {
                printstrln("USB sample buffer overflow");
                while(1);
            }
          #endif

          #if DEBUG == RX_SAMPLE
          if (left == 0)
          {
            testPort <: 0;
          }
          #endif

          break;
        }

        /////////////////////////////////////////
        // PWM requests the next sample to be interpolated.
        case c_pwmCntl :> pwmCntl:
        {
          if (active == TRUE)
          {
            // PWM thread wants a new sample interpolated.
            #if DEBUG == NEXT_SAMPLE
              if (left == 0)
              {
                testPort <: 1;
              }
            #endif

            if ((UsbSampleCheck[UsbSampleRdPtr] != UsbSampleRd) && (left == 0))
            {
              #if PRINT == USB_FLOW_CHECK
                printstr("USB Buf flow err.  Exp: 0x");
                printhex(UsbSampleRd);
                printstr("  Act: 0x");
                printhex(UsbSampleCheck[UsbSampleRdPtr]);
                printstr("  Count: ");
                printintln(UsbSampleCount);
                #if 0
                printstr("  UsbSampleRdPtr: 0x");
                printhexln(UsbSampleRdPtr);
                printstr("  UsbSampleRd: 0x");
                printhexln(UsbSampleRd);
                printstr("  UsbSampleWrPtr: 0x");
                printhexln(UsbSampleWrPtr);
                printstr("  UsbSampleWr: 0x");
                printhexln(UsbSampleWr);
                #endif
                while(1);
              #endif
            }
            UsbSampleRd ++;

            interpolate (UsbSample, UsbSampleRdPtr,
                         s2InputSamples, s2SampleHeadPtr,
                         #if SAMPLE_SOURCE == SINE_PWM_FIFO_WR
                           sampleNo,
                         #endif
                         pwmSampleFifo, pwmSampleFifoCheck, pwmFifoCheckVal, pwmSampleFifoPtr);

            #if DEBUG == NEXT_SAMPLE
              if (left == 0)
              {
                testPort <: 0;
              }
            #endif
            // PWM thread wants a new sample interpolated.
            UsbSampleRdPtr++;
            UsbSampleRdPtr &= USB_SAMPLE_BUFFER_PTR_MASK;
            UsbSampleCount--;

            #if DEBUG == BUFFER_LEVEL
              // If buffer getting too full slow down the sample receive rate
              if (UsbSampleCount < USB_SAMPLE_BUFFER_INIT+20)
              {
                  testPort <: 0;
              }
            #endif

            #if PRINT == USB_FLOW_CHECK
              if (UsbSampleCount < 0)
              {
                  printstrln("USB sample buffer underflow");
                  while(1);
              }
            #endif
          } // Not active yet
          break;
        } // case c_pwmCntl
      } // select
    } // while (active != RESET)
  } // while (1) with buffer init

}
#endif // CLASSD_OUTPUT
