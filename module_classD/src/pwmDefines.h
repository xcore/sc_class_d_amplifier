// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef PWMDEFINES_H_
#define PWMDEFINES_H_

// inline assember macros
#define CAST32(dst, src)       asm("mov %0, %1"     : "=r"(dst) : "r"(src));
#define LOAD32(dst, ptr)       asm("ldw %0, %1[0]"  : "=r"(dst) : "r"(ptr));
#define STORE32(src, ptr)      asm("stw %0, %1[0]"  :           : "r"(src), "r"(ptr));
#define MUL(dst, muld, mulr)   asm("mul %0, %1, %2" : "=r"(dst) : "r"(muld),"r"(mulr));
#define GETPS(dst, res)        asm("get %0, ps[%1]" : "=r"(dst) : "r"(res));
#define SETPS(src, res)        asm("set ps[%0], %1" :           : "r"(res), "r"(src));

#define FALSE 0
#define TRUE  1
#define RESET 2

//////////////////////////////////////////////////////
//#define USB_SAMPLE_BUFFER_SIZE_BITS           8
//#define USB_SAMPLE_BUFFER_SIZE                (1<<USB_SAMPLE_BUFFER_SIZE_BITS)
#define USB_SAMPLE_BUFFER_SIZE               256
#define USB_SAMPLE_BUFFER_INIT               128
//#define USB_SAMPLE_BUFFER_PTR_MASK            (USB_SAMPLE_BUFFER_SIZE-1)
#define USB_SAMPLE_BUFFER_PTR_MASK            255
//////////////////////////////////////////////////////

#define INTERPOLATION_RATIO       8  // Num S2 samples per raw sample

// Elements of the attribute array
#define SAMPLE_RATE_ELEM    0
#define PWM_PERIOD_ELEM     1
#define MS_DELAY_WHOLE_ELEM 2
#define MS_DELAY_FRAC_ELEM  3
#define VOLUME_ELEM         4
#define NUM_ATTR_ELEMS      5  // Size of shared array

#define PWM_PERIOD_48000 (DEF_REF_FREQ_MHz * 1000000 /(48000 * INTERPOLATION_RATIO)) // Using raw definition to avoid run time divide
#define PWM_PERIOD_44100 (DEF_REF_FREQ_MHz * 1000000 /(44100 * INTERPOLATION_RATIO)) // Using raw definition to avoid run time divide
#define PWM_PERIOD_32000 (DEF_REF_FREQ_MHz * 1000000 /(32000 * INTERPOLATION_RATIO)) // Using raw definition to avoid run time divide

#define MS_DELAY_WHOLE_48000 48
#define MS_DELAY_FRAC_48000   0
#define MS_DELAY_WHOLE_44100 44
#define MS_DELAY_FRAC_44100   1
#define MS_DELAY_WHOLE_32000 32
#define MS_DELAY_FRAC_32000   0
#define MS_DELAY_FRAC_LIMIT  10

//////////////////////////////////////
#define PWM_CNTL_START_PWM   1
#define PWM_CNTL_NEXT_SAMPLE 2
#define PWM_CNTL_STOP_PWM    3

#define DUMMY_SAMPLE_STOP     0x73333333  // Large value so replacement will have small effect
#define DUMMY_SAMPLE_REPLACE (DUMMY_SAMPLE_STOP-1)

// Fifos are twice the size of the interpolation ratio to allow one half to be written to whilst the other half is read
#define PWM_FIFO_SIZE          0x10 // (2*INTERPOLATION_RATIO)
#define PWM_FIFO_MASK          0x0f // (PWM_FIFO_SIZE -1)
#define PWM_FIFO_INIT          0x08 // (PWM_FIFO_SIZE >> 1) // Start off with this number of (zero) samples


// Different MOSFETs have different characteristics.
// Seperate the defintions and select the one being built
#define RC_FILTER       0   // No deadtime or extra hi cycles
#define FDS8858CZ       1   // driven by a gate driver chip FAN3227
#define FDS4897C        2   // driven by a gate driver chip FAN3227

#define BOARD      FDS4897C // RC_FILTER, FDS8858CZ, FDS4897C

////////////////////////////////////////////////////////////////////////
#if BOARD == RC_FILTER
  #define DEADTIME_PTYPE_ns         0  // Deadtime required in ns when this FET turns off
  #define DEADTIME_NTYPE_ns         0  // Deadtime required in ns when this FET turns off
  // Note that the output transitions when all fets are off, following one of them turning off
  #define HI_OFF_DELAY_ns           0 // The duration it takes from turning off the HiFET to the output transitioning
  #define LO_OFF_DELAY_ns           0 // The duration it takes from turning off the LoFET to the output transitioning
////////////////////////////////////////////////////////////////////////
#elif BOARD == FDS8858CZ
  // FAS8858 driven by an FAN3227
  #define DEADTIME_PTYPE_ns       100  // Deadtime required in ns when this FET turns off
  #define DEADTIME_NTYPE_ns        50  // Deadtime required in ns when this FET turns off
  // Note that the output transitions when all fets are off, following one of them turning off
  #define HI_OFF_DELAY_ns          80 // The duration it takes from turning off the HiFET to the output transitioning
  #define LO_OFF_DELAY_ns          44 // The duration it takes from turning off the LoFET to the output transitioning
////////////////////////////////////////////////////////////////////////
#elif BOARD == FDS4897C
  // FDS4897C driven by an FAN3227
  #define DEADTIME_PTYPE_ns       100 // Deadtime required in ns when this FET turns off
  #define DEADTIME_NTYPE_ns        50 // Deadtime required in ns when this FET turns off
  // Note that the output transitions when all fets are off, following one of them turning off
  #define HI_OFF_DELAY_ns          80 // The duration it takes from turning off the HiFET to the output transitioning
  #define LO_OFF_DELAY_ns          44 // The duration it takes from turning off the LoFET to the output transitioning
////////////////////////////////////////////////////////////////////////
#endif
// Convert times to cycles using the reference clock freq for this build
#define DEADTIME_HI2LO   ((DEADTIME_PTYPE_ns * DEF_REF_FREQ_MHz) /1000)
#define DEADTIME_LO2HI   ((DEADTIME_NTYPE_ns * DEF_REF_FREQ_MHz) /1000)
#define HI_OFF_DELAY     ((HI_OFF_DELAY_ns   * DEF_REF_FREQ_MHz) /1000)
#define LO_OFF_DELAY     ((LO_OFF_DELAY_ns   * DEF_REF_FREQ_MHz) /1000)

// Determined by trial and error to ensure that the minimum time from the first edge of one group of 4
// (this can potentially block for the maximum time)
// to the first edge in the next group is less than the time it takes to execute the SETPT/OUT instructions
// to schedule those edges.
// E.g. if it takes 15 instructions from the first SETPT to the last OUT, then 15instr*2ns*8threads=240ns
#define MODULATION_DEPTH_PBYTE 0xd0 // Per 256 (i.e. not percent(100))
                                    // 100% =0x100 Hi Distortion, Hi volume
                                    // 50%  =0x080 Lo distortion, lo volume

// The Hi side MOSFET may be n-type or p-type
#ifndef NTYPE_HI_FET
  // Lo driving FET is N-type
  // Hi driving FET is P-type
  #define LO_FET_ON  1
  #define LO_FET_OFF 0
  #define HI_FET_ON  0
  #define HI_FET_OFF 1
#else
  // Lo driving FET is N-type
  // Hi driving FET is N-type too
  #define LO_FET_ON  1
  #define LO_FET_OFF 0
  #define HI_FET_ON  1
  #define HI_FET_OFF 0
#endif

//////////////////////

// For debug sine waves can be injected at most stages of the flow

#define USB                0
#define SINE_PWM_FIFO_RD   1     // Replace samples with sine at the output of the PWM FIFO
#define SINE_PWM_FIFO_WR   2     // Replace samples with sine at the input  to the PWM FIFO
#define SINE_USB_FIFO_WR   3     // Replace samples with sine at the input  to the USB FIFO
#define SINE_USB_SPLIT     4     // Replace samples with sine when the combined stream is split
#define SAMPLE_SOURCE     USB

#if SAMPLE_SOURCE == SINE_PWM_FIFO_RD
  #define SAMPLE_INC       3  // 1152 No of sample increments per PWM cycle (@384kHz 1 = 384Hz, 3=1152Hz)
#elif SAMPLE_SOURCE == SINE_PWM_FIFO_WR
  #define SAMPLE_INC       2  //  768 No of sample increments per PWM cycle (@384kHz 1 = 384Hz, 3=1152Hz)
#elif SAMPLE_SOURCE == SINE_USB_FIFO_WR
  #define SAMPLE_INC      25  // 1200 No of sample increments per PWM cycle (@384kHz 1 = 384Hz, 3=1152Hz)
#elif SAMPLE_SOURCE == SINE_USB_SPLIT
  #define SAMPLE_INC      13  // 1200 No of sample increments per PWM cycle (@384kHz 1 = 384Hz, 3=1152Hz)
#endif

//////////////////////
// What do you want to debug
#define OFF 0
#define RX_SAMPLE 6          // pulse for each sample written into the USB buffer
                             // Should come in 1ms busts
#define NEXT_SAMPLE 2        // Pulses when the left thread receives the command from the PWM thread
                             // to interpolate the next sample.  Opposite of RX_SAMPLE
#define BUFFER_LEVEL 4       // 1 when the usb sample buffer is low and fast samples have been requested
#define DEBUG OFF


#define NO_PRINTING    0
#define USB_FLOW_CHECK 1     // *** USES PRINTS SO DISCONNECT PA POWER BEFORE USING **
                             // Inserts incremental values into the sample buffer
                             // then checks they are as expected at the receiver
                             // *** USES PRINTS SO DISCONNECT PA POWER BEFORE USING **
#define PWM_FLOW_CHECK 2
#define PRINT NO_PRINTING

#endif /*PWMDEFINES_H_*/




