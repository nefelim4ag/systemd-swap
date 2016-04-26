# systemd-swap
Script for auto-creation and mounting of: zram swaps, swap files (through loop) devices, swap partitions.
It is configurable in /etc/systemd-swap.conf.
Source:
```
/etc/systemd-swap.conf
/usr/lib/modprobe.d/90-systemd-swap.conf
/usr/lib/systemd/system/systemd-swap.service
/usr/lib/systemd/scripts/systemd-swap.sh
```
Using:
```
# systemctl enable systemd-swap
```
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch: in the [community](https://www.archlinux.org/packages/community/any/systemd-swap/).

Note:
=======
Dependence: util-linux >= 2.26

In package install /usr/lib/modprobe.d/90-systemd-swap.conf - this file create zram devices, 32 - this is maximum for this module.

You can use empty devices. 32 - because zram can't create new devices if others already in using, like loop module.
