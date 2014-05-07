# systemd-swap
Script for auto create and mount: zram swaps, swap files (through loop) devices, swap partitions
Num of zram devices = num of cpu's cores.
It configurable in /etc/systemd-swap.conf
Source:
```
/etc/systemd/system/systemd-swap.service
/etc/systemd-swap.conf
/usr/lib/systemd/scripts/systemd-swap.sh
```
Using:
```
# systemctl enable systemd-swap
```