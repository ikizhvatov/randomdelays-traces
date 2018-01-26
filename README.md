# Trace sets from SW AES impementation protected with random dealys

This repositroy contains tracesets from the following paper:

[Jean-Sébastien Coron and Ilya Kizhvatov. An Efficient Method for Random Delay Generation in Embedded Software. CHES 2009](https://www.iacr.org/archive/ches2009/57470156/57470156.pdf)

The tracesets were obtained from an 8-bit AVR microcontroller. The details on the measurement setup and the implementation are in the paper and in Sections 2.6.1 and 6.9 of [the thesis](https://www.iacr.org/phds/106_IlyaKizhvatov_PhysicalSecurityCryptographicA.pdf).

## Trace sets

`ctraces_fm16x4_2.mat` - SW AES with random delays implemented with the Floating mean method. Encryption key: `2b7e151628aed2a6abf7158809cf4f3c`.

To get the traces by cloning the repo, you need [Git LFS](https://git-lfs.github.com). Alternativey, you can download them directly from GitHub web interface.
