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
#include "global.h"

#ifdef CLASSD_OUTPUT
#ifndef CLASSD_INTEGRATION_EXAMPLE

#include <syscall.h>
#include <platform.h>
#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include "pwmDefines.h"
#include "audioManager.h"

// Share these attributes across the PWM threads
int attribute [NUM_ATTR_ELEMS] = { 48000,                // SAMPLE_RATE_ELEM
                                   PWM_PERIOD_48000,     // PWM_PERIOD_ELEM
                                   MS_DELAY_WHOLE_48000, // MS_DELAY_WHOLE_ELEM
                                   MS_DELAY_FRAC_48000,  // MS_DELAY_FRAC_ELEM
                                   0};                   // VOLUME_ELEM

// The interpolated samples are passed to the pwm thread through these Fifos for left and right data
int pwmSampleFifoL     [PWM_FIFO_SIZE];
int pwmSampleFifoLCheck[PWM_FIFO_SIZE];
int pwmSampleFifoR     [PWM_FIFO_SIZE];
int pwmSampleFifoRCheck[PWM_FIFO_SIZE];

// Function prototypes
void audioDac(streaming chanend c_dacL, streaming chanend pwmTimingLChan,
               int pwmSampleFifo[PWM_FIFO_SIZE],
               int pwmSampleFifoCheck[PWM_FIFO_SIZE],
               int left,
               out port ?testPort);
void pwmThread (s_audio &audioports, streaming chanend pwmTimingLChan, streaming chanend pwmTimingRChan);

/////////////////////////////////////
// This averages to 1ms.
// It is the exact time it takes to process 1ms worth of samples
int SOFdelay (int &SOFfractionalDelay)
{
  // For 44.1 most 1ms durations have 44 samples, but 1 in 10 has 45
  SOFfractionalDelay += attribute[MS_DELAY_FRAC_ELEM];
  if (SOFfractionalDelay == MS_DELAY_FRAC_LIMIT)
  {
     // Extra sample cycle this time
     SOFfractionalDelay = 0;
     return (attribute[PWM_PERIOD_ELEM] * INTERPOLATION_RATIO * (attribute[MS_DELAY_WHOLE_ELEM]+1));
  } else
  {
     return (attribute[PWM_PERIOD_ELEM] * INTERPOLATION_RATIO * (attribute[MS_DELAY_WHOLE_ELEM]  ));
  }
}

#if SAMPLE_SOURCE == SINE_USB_SPLIT
  extern int sineWave1000[1000];
  int sampleNo = 0;
#endif

/////////////////////////////////////
void audioManager(
    streaming_chanend cAudioStreaming, streaming chanend cSOFGen, streaming chanend cAudioMixer,
    s_audio &audioports, streaming chanend cAudioDFU)
{
  timer tSOF;
  streaming chan c_sampleL;       // raw channel samples
  streaming chan c_sampleR;       // raw channel samples
  streaming chan pwmTimingLChan;  // timing info from pwm thread to interpolation thread: start interpolating next sample
  streaming chan pwmTimingRChan;  // timing info from pwm thread to interpolation thread: start interpolating next sample
  int timeSOF;
  unsigned sample;
  int cmd;
  int SOFfractionalDelay = 0;
  int sampleLeftNext = TRUE;

  // First spawn interpolation and PWM threads
  par
  {
      audioDac(c_sampleL, pwmTimingLChan, pwmSampleFifoL, pwmSampleFifoLCheck, 1, null); // null );
      audioDac(c_sampleR, pwmTimingRChan, pwmSampleFifoR, pwmSampleFifoRCheck, 0, null); // audioports.loFetGateL); // null );
      pwmThread(audioports, pwmTimingLChan, pwmTimingRChan);

    {
      ///////////////////////////////////////////
      // This is another thread which controls
      //  1. SOF generation
      //  2. volume changes
      //  3. sample rate changes
      //  4. splits L&R sample data
      ///////////////////////////////////////////

      // Tell EP manager we do not require notification on device disconnect
      cAudioStreaming <: 0;

      // Init time and send first SOF req out without needing to input the ack first
      tSOF :> timeSOF;
      cSOFGen <: 1;
      timeSOF += SOFdelay(SOFfractionalDelay);

      while (1)
      {
        // ensure that the SOF takes priority in the select statement
        #pragma ordered
        select
        {
          ///////////////////////////
          // Initiate the next frame
          // This must be highest priority
          case tSOF when timerafter(timeSOF) :> int _ :
            // Increase timer for next SOF
            timeSOF += SOFdelay(SOFfractionalDelay);

            // Don't make a SOF request until the previous one has finished,
            // but don't pause waiting for the ack, if it's not been issued.
            // This thread must still be able to respond to cAudioMixer commands
            select
            {
              // Only req if the last req has been acked
              case cSOFGen :> int _:
                //      audioports.hiFetGateL <: 1;
                //      audioports.hiFetGateL <: 0;
                cSOFGen <: 1;
                break;
              default:
                break;
            }
            break;

          ///////////////////////////
          // get the audio samples
          case AUDIO_STREAMING_INPUT(cAudioStreaming, sample):

            sample <<= 16;
            #if SAMPLE_SOURCE == SINE_USB_SPLIT
              // Inject a sine wave into the stream
              sample = sineWave1000[sampleNo];
              sampleNo+=SAMPLE_INC;
              if (sampleNo >= 1000)
              {
                sampleNo -= 1000;
              }
            #endif


            // The sample channel is used to transmit a stop signal
            // Avoid this value being used by a real sample by replacing it with a similar value
            if (sample == DUMMY_SAMPLE_STOP)
            {
              sample = DUMMY_SAMPLE_REPLACE;
            }

            if (sampleLeftNext == TRUE)
            {
              c_sampleL <: sample;
              sampleLeftNext = FALSE;
            } else
            {
              c_sampleR <: sample;
              sampleLeftNext = TRUE;
            }
            //      audioports.loFetGateL <: 0;
            //      audioports.loFetGateL <: 1;
            break;

          ///////////////////////////
          // Volume and rate changes
          case cAudioMixer :>  cmd:
          {
            switch (cmd)
            {
              case 1:
                break;
              case 2:
                // Change audio rate
                {
                  int rate; // 48000, 44100 or 32000
                  int waitingForAck = 1;
                  cAudioMixer :> attribute[SAMPLE_RATE_ELEM];        // Get the new rate
                  cAudioMixer <: 0;           // Acknowledge reciept of new rate

                  switch (attribute[SAMPLE_RATE_ELEM])
                  {
                    case 48000:
                      attribute[PWM_PERIOD_ELEM]     = PWM_PERIOD_48000;
                      attribute[MS_DELAY_WHOLE_ELEM] = MS_DELAY_WHOLE_48000;
                      attribute[MS_DELAY_FRAC_ELEM]  = MS_DELAY_FRAC_48000;
                      break;
                    case 44100:
                      attribute[PWM_PERIOD_ELEM]     = PWM_PERIOD_44100;
                      attribute[MS_DELAY_WHOLE_ELEM] = MS_DELAY_WHOLE_44100;
                      attribute[MS_DELAY_FRAC_ELEM]  = MS_DELAY_FRAC_44100;
                      break;
                    case 32000:
                      attribute[PWM_PERIOD_ELEM]     = PWM_PERIOD_32000;
                      attribute[MS_DELAY_WHOLE_ELEM] = MS_DELAY_WHOLE_32000;
                      attribute[MS_DELAY_FRAC_ELEM]  = MS_DELAY_FRAC_32000;
                      break;
                    default:
                      // error
                      break;
                  }

                  // Tell interpolation threads to clear buffers
                  c_sampleL <: DUMMY_SAMPLE_STOP;
                  c_sampleR <: DUMMY_SAMPLE_STOP;

                  // Continue Issuing SOF requests until we get acknowledgement that the
                  // rate change has been implemented
                  while (waitingForAck)
                  {
                    select
                    {
                      // Issue SOF requests
                      case tSOF when timerafter(timeSOF) :> int _:
                        timeSOF += SOFdelay(SOFfractionalDelay);
                        // Only issue a new req when the previous ack has been received
                        select
                        {
                          case cSOFGen :> int _:
                            //      audioports.hiFetGateL <: 1;
                            //      audioports.hiFetGateL <: 0;
                            cSOFGen <: 1;
                            break;
                          default:
                            break;
                        }
                        break;
                      // Resume main code when the rate change ack is recieved
                      case cAudioMixer :> int _:
                        waitingForAck = 0;
                        break;
                    }
                  }

                }
                break;
              case 4:
              {
                int volumeRaw;  // 0 for off, 0x100 for max (convert to 0x7fffffff)
                                // I think this scale is linear
                                // Need to implement logrithmic volume
                                // vol^4 is approx log for values < 1 (apparently)

                cAudioMixer :> volumeRaw;         // Get the new volume
                if (volumeRaw == 0)
                {
                  attribute[VOLUME_ELEM] = 0;
                } else
                {
                  //
                  int volume;
                  int volHi, volLo;
                  volume = volumeRaw << (30-8); // 0x40000000 for 0x100 (max vol)
                  {volHi, volLo} = mac (volume, volume, 0, 0);
                  volume = volHi << 2;
                  {volHi, volLo} = mac (volume, volume, 0, 0);
                  volume = (volHi << 3)-1;
                  attribute[VOLUME_ELEM] = volume;                   // vol^4
                }
                break;
              }
              default:
                vprintstr("cAudioMixer default: ");
                vprintintln(cmd);

                break;
            } // switch
            break; // for select
          } // case cAudioMixer :> cmd:
        } // select
      } // while(1)
    } // This thread
  } // par
}


#endif // CLASSD_INTEGRATION_EXAMPLE
#endif // CLASSD_OUTPUT
