# systemd-swap
Script for auto-creation and mounting of: zram swaps, swap files (through loop) devices, swap partitions.
It is configurable in /etc/systemd-swap.conf.
Source:
```
/etc/systemd-swap.conf
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
