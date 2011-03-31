// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/**
 * @file pwm.xc
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
#include "audioManager.h"

// C function for reading the shared memory
int fifoRead (int fifoBasePtr, int fifoPtrPtr, int fifoCheckBasePtr, int fifoCheckVal);  // fifoBasePtr is a pointer to the arrayBase, fifoPtrPtr is a pointer to the fifo pointer
int attr (int element);

#if (DEBUG != OFF)
  extern  out port testPortL; //
#endif

#if SAMPLE_SOURCE == SINE_PWM_FIFO_RD
  extern int sineWave1000[1000];
  int       sampleNo = 0; // Used to index sine table
#endif
////////////////////////////////////

// Adjust the modulation depth
#define PWM_SAMPLE_BINARY_POINT      31 // Binary point after this bit
#define PWM_ZERO_BITS                30 // A zero sample is conditioned to 1<< PWM_ZERO_BITS
#define MODULATION_DEPTH_MULTIPLIER  (MODULATION_DEPTH_PBYTE<<(32+PWM_ZERO_BITS-PWM_SAMPLE_BINARY_POINT-8))

#if 1 // Do not use a dummy pwmThread, use the real one
////////////////////////////////////
void pwmThread (s_audio &audioports, streaming chanend pwmTimingLChan, streaming chanend pwmTimingRChan)
{

  unsigned  fracErrorL = 0;
  unsigned  fracErrorR = 0;
  unsigned  portTimeStart;     // port time at the start of the PWM cycle

  unsigned  pwmPeriod    = PWM_PERIOD_48000;

  int pwmSampleFifoLbase;    // Fifo array.  Address from interpolate thread.
  int pwmSampleFifoRbase;    // Fifo array.  Address from interpolate thread.
  int pwmSampleFifoLCheckbase;    //
  int pwmSampleFifoRCheckbase;    //
  int pwmSampleFifoLptr [1] = {0}; // points to the next location to read from
  int pwmSampleFifoRptr [1] = {0}; // points to the next location to read from
  int pwmSampleFifoLptrPtr; // points to the next location to read from
  int pwmSampleFifoRptrPtr; // points to the next location to read from

  unsigned  upStepLTimeNext;                          // Num ref clk ticks that the PWM is hi for
  unsigned  upStepLTimeThis = PWM_PERIOD_48000 >> 1;  // Num ref clk ticks that the PWM is hi for
  unsigned  upStepRTimeNext;                          // Num ref clk ticks that the PWM is hi for
  unsigned  upStepRTimeThis = PWM_PERIOD_48000 >> 1;  // Num ref clk ticks that the PWM is hi for

  int       timingCount  = 0; // used to track when to send sync to interpolation thread
  int       pwmFifoCount = 0; // Counts the pwm samples to check for missing samples

  //////////////////////////////////////////////////////////
  // Initialisation
  //////////////////////////////////////////////////////////

  // Get the base address of the fifos shared between threads
  pwmTimingLChan :> pwmSampleFifoLbase;
  pwmTimingRChan :> pwmSampleFifoRbase;
  pwmTimingLChan :> pwmSampleFifoLCheckbase;
  pwmTimingRChan :> pwmSampleFifoRCheckbase;

  // Need a pointer to the fifoReadPointer, so the read function can increment the pointer
  CAST32(pwmSampleFifoLptrPtr, pwmSampleFifoLptr);
  CAST32(pwmSampleFifoRptrPtr, pwmSampleFifoRptr);

  // Wait for start commands from both channels before proceeding
  {
    int cmd;
    int activeL = FALSE;
    int activeR = FALSE;
    while ((activeL != TRUE) || (activeR != TRUE))
    // See if either channel has asked the PWM to stop
    select
    {
      case pwmTimingLChan :> cmd:
      {
        if (cmd == PWM_CNTL_START_PWM)
        {
          activeL = TRUE;
        } else
        {
          activeL = FALSE;
        }
        break;
      }
      case pwmTimingRChan :> cmd:
      {
        if (cmd == PWM_CNTL_START_PWM)
        {
          activeR = TRUE;
        } else
        {
          activeR = FALSE;
        }
        break;
      }
    }
  }
  pwmPeriod = attr(PWM_PERIOD_ELEM); // Use the latest sample rate

  // Start dsp threads interpolating next sample
  pwmTimingLChan <: PWM_CNTL_NEXT_SAMPLE;
  pwmTimingRChan <: PWM_CNTL_NEXT_SAMPLE;

  audioports.hiFetGateL <: HI_FET_OFF;
  audioports.loFetGateL <: LO_FET_OFF;
  audioports.hiFetGateR <: HI_FET_OFF;
  audioports.loFetGateR <: LO_FET_OFF @ portTimeStart; // Get portTimeL

  while(1)
  {

    int       sampleLRaw;             // Raw interpolated sample
    unsigned  sampleLCond;            // Conditioned sample has dc offset so 0 is 50:50 PWM
    int       sampleLCondHi;
    unsigned  sampleLCondLo;
    unsigned  upStepLHi;              // 64 bit upStep duration result, adding in fractional error from prev cycle
    unsigned  upStepLLo;
    int       volLHi;
    unsigned  volLLo;
    int       volumeL;

    int       sampleRRaw;
    unsigned  sampleRCond;
    int       sampleRCondHi;
    unsigned  sampleRCondLo;
    unsigned  upStepRHi;
    unsigned  upStepRLo;
    int       volRHi;
    unsigned  volRLo;
    int       volumeR;

    unsigned  portTimeL;         // port time for L samples
    unsigned  portTimeR;         // port time for R samples

    #if SAMPLE_SOURCE == SINE_PWM_FIFO_RD
      // Inject sine wave instead of audio stream
      sampleLRaw = sineWave1000[sampleNo];
      sampleRRaw = sineWave1000[sampleNo];
      sampleNo+=SAMPLE_INC;
      if (sampleNo >= 1000)
      {
        sampleNo -= 1000;
      }
    #else
      // Obtain pwm freq samples from fifo
      sampleLRaw = fifoRead (pwmSampleFifoLbase, pwmSampleFifoLptrPtr, pwmSampleFifoLCheckbase, pwmFifoCount);
      sampleRRaw = fifoRead (pwmSampleFifoRbase, pwmSampleFifoRptrPtr, pwmSampleFifoRCheckbase, pwmFifoCount);
      pwmFifoCount++;
    #endif

    // Volume control
    // e.g. for PWM_ZERO_BITS == 30
    // {2q62} =                    1q31              , 1q31
    volumeL = attr(VOLUME_ELEM);
    {volLHi, volLLo} = macs (volumeL, MODULATION_DEPTH_MULTIPLIER, 0, 0);
    volumeL = volLHi<<1;
    volumeR = volumeL;

    // s2Sample is 1q31, but sampleCond should be unsigned with a FS signal using 22bits
    // s2Sample 7fff_ffff maps to sampleCond=FFFF_FFFF (for 100% modulation depth); BFFF_FFFF (for 50% modulation depth)
    // s2Sample 4000_0000 maps to sampleCond=C000_0000 (for 100% modulation depth); A000_0000 (for 50% modulation depth)
    // s2Sample         0 maps to sampleCond=8000_0000 (for 100% modulation depth); 8000_0000 (for 50% modulation depth)
    // s2Sample c000_0000 maps to sampleCond=4000_0000 (for 100% modulation depth); 6000_0000 (for 50% modulation depth)
    // s2Sample 8000_0000 maps to sampleCond=0000_0000 (for 100% modulation depth); 4000_0000 (for 50% modulation depth)

    {sampleLCondHi, sampleLCondLo} = macs (sampleLRaw, volumeL, (1 << PWM_ZERO_BITS), 0);
    {sampleRCondHi, sampleRCondLo} = macs (sampleRRaw, volumeR, (1 << PWM_ZERO_BITS), 0);

    #define SAMPLE_COND_BINARY_POINT 31
    sampleLCond =  (unsigned)(sampleLCondHi <<     (SAMPLE_COND_BINARY_POINT-PWM_ZERO_BITS) )
                 + (unsigned)(sampleLCondLo >> (32-(SAMPLE_COND_BINARY_POINT-PWM_ZERO_BITS)));
    sampleRCond =  (unsigned)(sampleRCondHi <<     (SAMPLE_COND_BINARY_POINT-PWM_ZERO_BITS) )
                 + (unsigned)(sampleRCondLo >> (32-(SAMPLE_COND_BINARY_POINT-PWM_ZERO_BITS)));
    // Scale the sample and add in the error
    {upStepLHi, upStepLLo} = mac (sampleLCond, pwmPeriod, 0, fracErrorL);
    {upStepRHi, upStepRLo} = mac (sampleRCond, pwmPeriod, 0, fracErrorR);

    // Adjust for mismatches in lo and hi delay
    // The delay is the time it takes from changing the gate to turn the FET off, until the (loaded) output changes
    // Matching these allows the maximum volume to be attained.
    upStepLTimeNext = upStepLHi - (LO_OFF_DELAY - HI_OFF_DELAY);
    upStepRTimeNext = upStepRHi - (LO_OFF_DELAY - HI_OFF_DELAY);

    fracErrorL = upStepLLo;
    fracErrorR = upStepRLo;

    // All cycles start and end with a hi with a lo section in the middle
    // Schedule end of high section
    {
      // The maximum volume is determined by the time it takes to execute code from the first, possibly blocking SETPT
      // to the last setPT in a block of 4.
      // So compute all port times up front then issue all SETPT/OUTs together in a block with deadtimes first
      int hiFetGateLpt;
      int loFetGateLpt;
      int hiFetGateRpt;
      int loFetGateRpt;

      portTimeL = portTimeStart + (upStepLTimeThis >> 1);
      hiFetGateLpt = portTimeL - HI_OFF_DELAY;
      loFetGateLpt = hiFetGateLpt + DEADTIME_HI2LO;
      portTimeR = portTimeStart + (upStepRTimeThis >> 1);
      hiFetGateRpt = portTimeR - HI_OFF_DELAY;
      loFetGateRpt = hiFetGateRpt + DEADTIME_HI2LO;

      audioports.hiFetGateL @ hiFetGateLpt <: HI_FET_OFF;
      audioports.hiFetGateR @ hiFetGateRpt <: HI_FET_OFF;
      audioports.loFetGateL @ loFetGateLpt <: LO_FET_ON;
      audioports.loFetGateR @ loFetGateRpt <: LO_FET_ON;

      portTimeL += (pwmPeriod - upStepLTimeThis);
      loFetGateLpt = portTimeL - LO_OFF_DELAY;
      hiFetGateLpt = loFetGateLpt + DEADTIME_LO2HI;
      portTimeR += (pwmPeriod - upStepRTimeThis);
      loFetGateRpt = portTimeR - LO_OFF_DELAY;
      hiFetGateRpt = loFetGateRpt + DEADTIME_LO2HI;

      audioports.loFetGateL @ loFetGateLpt <: LO_FET_OFF;
      audioports.loFetGateR @ loFetGateRpt <: LO_FET_OFF;
      audioports.hiFetGateL @ hiFetGateLpt <: HI_FET_ON;
      audioports.hiFetGateR @ hiFetGateRpt <: HI_FET_ON;
    }

    portTimeStart += pwmPeriod;

    // Move onto the next sample
    upStepLTimeThis = upStepLTimeNext;
    upStepRTimeThis = upStepRTimeNext;

    // Tell interpolation thread when to analyse the next sample
    timingCount++;

    if (timingCount == INTERPOLATION_RATIO)
    {
      // Tell the interpolation threads to interpolate the next sample
      pwmTimingLChan <: PWM_CNTL_NEXT_SAMPLE;
      pwmTimingRChan <: PWM_CNTL_NEXT_SAMPLE;
      timingCount = 0;
    } else
    {
      int cmd;
      int activeL = TRUE;
      int activeR = TRUE;
      // See if either channel has asked the PWM to stop
      select
      {
        case pwmTimingLChan :> cmd:
          {
            if (cmd == PWM_CNTL_STOP_PWM)
            {
              activeL = FALSE;
            }
            break;
          }
        case pwmTimingRChan :> cmd:
          {
            if (cmd == PWM_CNTL_STOP_PWM)
            {
              activeL = FALSE;
            }
            break;
          }
        default:
          break;
      }

      // Continue when both channels are active
      while ((activeL == FALSE) || (activeR == FALSE))
      {

        // Turn active ports off
        audioports.hiFetGateL <: HI_FET_OFF;
        audioports.hiFetGateR <: HI_FET_OFF;

        select
        {
          case pwmTimingLChan :> cmd :
            {
              if (cmd == PWM_CNTL_START_PWM)
              {
                activeL = TRUE;
              } else if (cmd == PWM_CNTL_STOP_PWM)
              {
                activeL = FALSE;
              }
            }
            break;
          case pwmTimingRChan :> cmd :
            {
              if (cmd == PWM_CNTL_START_PWM)
              {
                activeR = TRUE;
              } else if (cmd == PWM_CNTL_STOP_PWM)
              {
                activeR = FALSE;
              }
            }
            break;
        } // select


        pwmPeriod = attr(PWM_PERIOD_ELEM); // Use the latest sample rate
        pwmFifoCount = 0; // restart pwm sample counter
        pwmSampleFifoLptr [0] = 0; // And start from the first location in the FIFO again
        pwmSampleFifoRptr [0] = 0;

        // Get the port time for when loop exits
        audioports.hiFetGateL <: HI_FET_OFF;
        audioports.loFetGateL <: LO_FET_OFF;
        audioports.hiFetGateR <: HI_FET_OFF;
        audioports.loFetGateR <: LO_FET_OFF @ portTimeStart; // Get portTimeL
      }

    } // not an interpolation count sample
  } // while(1)
}
#endif // Not the dummy pwm thread


#if 0 // dummy timer based pwm thread

void pwmThread (s_audio &audioports, streaming chanend pwmTimingLChan, streaming chanend pwmTimingRChan)
{
  unsigned int  pwmSampleFifoLbase;
  unsigned int  pwmSampleFifoRbase;
  unsigned int  pwmSampleFifoLcheckBase;
  unsigned int  pwmSampleFifoRcheckBase;
  unsigned int  pwmCntl=0;


  timer sampleTimer;
  int   sampleTime;
  int   cmd;

  int activeL = FALSE;
  int activeR = FALSE;


  pwmTimingLChan :> pwmSampleFifoLbase;
  pwmTimingRChan :> pwmSampleFifoRbase;
  pwmTimingLChan :> pwmSampleFifoLcheckBase;
  pwmTimingRChan :> pwmSampleFifoRcheckBase;
  // Wait for start of samples:
  pwmTimingLChan :> pwmCntl;
  pwmTimingRChan :> pwmCntl;


  sampleTimer :> sampleTime;

  while (1)
  {
    int pwm_period;

    pwm_period = attr(PWM_PERIOD_ELEM);

    sampleTime = sampleTime + (pwm_period * INTERPOLATION_RATIO);

    audioports.hiFetGateR <: 1;
    sampleTimer when timerafter (sampleTime) :> void;
    audioports.hiFetGateR <: 0;

    // Indicate to the interpolation thread to start another sample
    pwmTimingLChan <: PWM_CNTL_NEXT_SAMPLE;
    pwmTimingRChan <: PWM_CNTL_NEXT_SAMPLE;

    // See if either channel has asked the PWM to stop
    select
    {
      case pwmTimingLChan :> cmd:
        {
          if (cmd == PWM_CNTL_STOP_PWM)
          {
            activeL = FALSE;
          }
          break;
        }
      case pwmTimingRChan :> cmd:
        {
          if (cmd == PWM_CNTL_STOP_PWM)
          {
            activeL = FALSE;
          }
          break;
        }
      default:
        break;
    }

    // Continue when both channels are active
    while ((activeL == FALSE) || (activeR == FALSE))
    {
      int cmd;

      select
      {
        case pwmTimingLChan :> cmd :
          {
            if (cmd == PWM_CNTL_START_PWM)
            {
              activeL = TRUE;
            } else if (cmd == PWM_CNTL_STOP_PWM)
            {
              activeL = FALSE;
            }
          }
          break;
        case pwmTimingRChan :> cmd :
          {
            if (cmd == PWM_CNTL_START_PWM)
            {
              activeR = TRUE;
            } else if (cmd == PWM_CNTL_STOP_PWM)
            {
              activeR = FALSE;
            }
          }
          break;
      } // select

      // Restart the pwm time if we're waiting to start
      sampleTimer :> sampleTime;
    } // Wait until both channels are active
  } // while (1)
}
#endif // dummy timer based pwm thread

#endif // CLASSD_OUTPUT
