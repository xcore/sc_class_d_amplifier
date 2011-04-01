Class D Amplifier
.................

:Stable release:  None

:Status:  draft

:Maintainer:  https://github.com/ChippendaleMupp

:Description:  A brief description of the repo


Key Features
============

* Stereo Open Loop ClassD amplifier
* PWM outputs at 8x sample frequency
* Supports 48.0, 44.1 and 32kHz sample frequencies

To Do
=====

* No outstanding missing features

Firmware Overview
=================

The example application produces samples for a 1kHz sine wave on both channels at 48kHz.  The samples are interpolated upto 384kHz via 96kHz.  They are then output in PWM on two 1 bit ports per channel.  Two 1 bit ports are required per channel to introduce deadtime to avoid shoot-through current.

This code has been release to github from xmos.com's example application code.  There are two documents support this code: "Class D Audio Power Amplifier" (Class-D-Audio-Power-Amplifier.pdf) and "Class D Audio Power Amplifier - iPod Dock" (Class-D-Audio-Power-Amplifier---iPod-Dock.pdf).  These have been copied to this repository for reference.


Known Issues
============

* None

Required Repositories
================

* xcommon git\@github.com:xcore/xcommon.git

Support
=======

<Description of support model>
