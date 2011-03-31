// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <platform.h>
#include <xs1.h>
#include "pwmDefines.h"
#include "audioManager.h"

#define SAMPLE_INC 21 // 1000sample LUT /(48000Hz samples /  1000Hz output)

// Function prototypes
void audioDac(streaming chanend c_dacL, streaming chanend pwmTimingLChan,
               int pwmSampleFifo[PWM_FIFO_SIZE],
               int pwmSampleFifoCheck[PWM_FIFO_SIZE],
               int left,
               out port ?testPort);

void pwmThread (s_audio &audioports, streaming chanend pwmTimingLChan, streaming chanend pwmTimingRChan);

s_audio audioports =
{
    XS1_PORT_1I, // PORT_SPDIF,      // hiFetGateL
    XS1_PORT_1K, // PORT_DAC_LRCLK,  // loFetGateL
    XS1_PORT_1L, // PORT_DAC_MCLK,   // hiFetGateR
    XS1_PORT_1M, // PORT_DAC_DATA    // loFetGateR
};

// Share these attributes across the PWM threads
int attribute [NUM_ATTR_ELEMS] = { 48000,                // SAMPLE_RATE_ELEM
                                   PWM_PERIOD_48000,     // PWM_PERIOD_ELEM
                                   MS_DELAY_WHOLE_48000, // MS_DELAY_WHOLE_ELEM
                                   MS_DELAY_FRAC_48000,  // MS_DELAY_FRAC_ELEM
                                   0x7fffffff};          // VOLUME_ELEM

// The interpolated samples are passed to the pwm thread through these Fifos for left and right data
int pwmSampleFifoL     [PWM_FIFO_SIZE];
int pwmSampleFifoLCheck[PWM_FIFO_SIZE];
int pwmSampleFifoR     [PWM_FIFO_SIZE];
int pwmSampleFifoRCheck[PWM_FIFO_SIZE];

extern int sineWave1000[1000];

int main ()
{
  streaming chan c_sampleL;       // raw channel samples
  streaming chan c_sampleR;       // raw channel samples
  streaming chan pwmTimingLChan;  // timing info from pwm thread to interpolation thread: start interpolating next sample
  streaming chan pwmTimingRChan;  // timing info from pwm thread to interpolation thread: start interpolating next sample

  // Configure the reference clock
  write_sswitch_reg(get_core_id(), XS1_L_SSWITCH_REF_CLK_DIVIDER_NUM, DEF_REF_CLK_DIV);

  par
  {
    audioDac(c_sampleL, pwmTimingLChan, pwmSampleFifoL, pwmSampleFifoLCheck, 1, null); // null );
    audioDac(c_sampleR, pwmTimingRChan, pwmSampleFifoR, pwmSampleFifoRCheck, 0, null); // audioports.loFetGateL); // null );
    pwmThread(audioports, pwmTimingLChan, pwmTimingRChan);
    {
      int       sampleNo = 0; // Used to index sine table
      int       sampleTime = 0;
      timer     sampleTimer_t;

      sampleTimer_t :> sampleTime;
      while (1)
      {
        sampleTime += PWM_PERIOD_48000* INTERPOLATION_RATIO;
        sampleTimer_t when timerafter (sampleTime) :> void;

        c_sampleL <: sineWave1000[sampleNo];
        c_sampleR <: sineWave1000[sampleNo];
        sampleNo+=SAMPLE_INC;
        if (sampleNo >= 1000)
        {
          sampleNo -= 1000;
        }

      } // while (1)
    }
  }

}
