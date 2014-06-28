## 2.22
Added support for zram's lz4 alg

## 2.21
Added description to 90-systemd-swap.conf
Polished script logic

## 2.20
From now:

By default always aviable 32 zram devices. This specify in:
```
/etc/modprobe.d/90-systemd-swap.conf
```
All options by default disabled, you need enable what you need manualy.

Added option to Enable/Disable cache of config file.

## 2.19
Add support, for create aditional empty zram devices.
several small fixes.

## 2.18
Fix issues with command run order
Deleted wrong line about systemctl reset.

## 2.17
Swappiness tuner deleted
Small code cleanups
Deleted modprobe for loopdevs

## 2.16
Now in modprobe adding only needed lines
Added zswap handler


## 2.15
Bug fix: reset function, after upgrading from very old version.
Bug fix: systemd-swap.sevice file - restore content.

## 2.14
Bug Fix: adding empty value in cache for swap devices array
Fix: included files in PKGBUILD
Add: Replaces and conflicts in PKGBUILD.