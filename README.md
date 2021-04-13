# Trace sets with random delays

This repository contains tracesets and code from the following paper:

[Jean-Sébastien Coron and Ilya Kizhvatov. An Efficient Method for Random Delay Generation in Embedded Software. CHES 2009](https://www.iacr.org/archive/ches2009/57470156/57470156.pdf)

The trace sets were obtained from an 8-bit AVR microcontroller. The details on the measurement setup and the implementation are in the paper and in Sections 2.6.1 and 6.9 of [the thesis](https://www.iacr.org/phds/106_IlyaKizhvatov_PhysicalSecurityCryptographicA.pdf).

## Trace sets

* `ctraces_fm16x4_2.mat` - AES-128 with random delays generated using the Floating mean method. Encryption key: `2b7e151628aed2a6abf7158809cf4f3c`. These power traces are compressed by selecting 1 sample (peak) of each CPU clock cycle. At least the first (non-dummy) AES round is covered.

To get the traces by cloning the repo you need [Git LFS](https://git-lfs.github.com). Alternatively, you can download the traces directly from GitHub web interface.

## Implementation

AVR assembler implementation with all the methods, AVR Studio 4 project.

## Acquisition scripts

MATLAB code for acquisition with LeCroy WaveRunner 104MXi oscilloscope, and for trace compressionsss.

## Licenses

<a rel="license" href="http://creativecommons.org/licenses/by-nc/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-nc/4.0/88x31.png" /></a><br />Traces are licensed under a <a rel="license" href="http://creativecommons.org/licenses/by-nc/4.0/">Creative Commons Attribution-NonCommercial 4.0 International License</a>

Implementation and acquisition scripts: [MIT License](LICENSE.MIT)
