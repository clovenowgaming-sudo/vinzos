VinzOS - which folder do I use?

  vinzos-64bit/vinzos-64bit.iso   Almost every PC or laptop made after 2006.
  vinzos-32bit/vinzos-32bit.iso   Old 32-bit-only PCs and netbooks.

Not sure? Try the 64-bit one first. If it does not boot, use the 32-bit one.

How to boot
  1. Write the .iso to a USB flash drive (Rufus in "DD image" mode, balenaEtcher, or the dd command).
  2. Boot the computer from the USB drive in Legacy / BIOS (CSM) mode.
  3. Virtual machines: attach the .iso as a CD-ROM.

Each folder also has bzImage + initramfs.gz for emulators that boot a kernel directly.
This version boots on BIOS / Legacy mode only (UEFI support is planned).
