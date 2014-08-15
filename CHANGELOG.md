## 2.24.7
==================
Loop devices use file descriptor for file acces ->
file can be safety deleted after setup loop device.
Small optimization in logics of swap file.

## 2.24.6
==================
Swapon as now trying to discard for swap files and swap partitions
Systemd as now, not tracking startup time to systemd-swap

## 2.24.5
==================
Added comments in code
Rework comments in systemd-swap.conf
Add note, what zram[streams] and zram[alg] working only on kernels >= 3.15
Fixes in modprobe config and small fixes in code
Use autoclear flag for loop devices, instead of manually detaching of file

## 2.24
==================
Move part of code, for setup zram device to external tool https://github.com/Nefelim4ag/zramctl

## 2.23
==================
  * Code and functionally cleanups.
  * Remove support for cache config, zswap parsing and multi files swap files.
  * Using bash associative arrays for more code clarity.
  * Add utility "write" function.
  * As now using only one zram device, because zram has a mechanism for multiple compression threads (added in config).
  * And as now script using first available free zram device, no hardcoded to zram{0..*}.
  * Module parse dev rewrited, feel free to send bug reports.
P.S. New config have new variables, replace old config with new

## 2.22
==================
Added support for zram's lz4 alg

## 2.21
==================
Added description to 90-systemd-swap.conf
Polished script logic

## 2.20
==================
From now:

By default always aviable 32 zram devices. This specify in:
```
/etc/modprobe.d/90-systemd-swap.conf
```
All options by default disabled, you need enable what you need manualy.

Added option to Enable/Disable cache of config file.

## 2.19
==================
Add support, for create aditional empty zram devices.
several small fixes.

## 2.18
==================
Fix issues with command run order
Deleted wrong line about systemctl reset.

## 2.17
==================
Swappiness tuner deleted
Small code cleanups
Deleted modprobe for loopdevs

## 2.16
==================
Now in modprobe adding only needed lines
Added zswap handler


## 2.15
==================
Bug fix: reset function, after upgrading from very old version.
Bug fix: systemd-swap.sevice file - restore content.

## 2.14
==================
Bug Fix: adding empty value in cache for swap devices array
Fix: included files in PKGBUILD
Add: Replaces and conflicts in PKGBUILD.