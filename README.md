systemd-swap
Simple script to auto create zram and swap file (through loop) devices and swapon it to system
Now ZRam does this - autocreate numbers of devices = numbers of 
CPU.
It configurable in /etc/systemd-swap.conf
/etc/systemd/system/systemd-swap.service
/etc/systemd-swap.conf
/usr/lib/systemd/scripts/systemd-swap.sh

TODO:
Dynamic increasing size of swap file
Auto using direct method (without loop) to using swap files on friendly for swap file fs (ext(4,3,2),xfs & etc)
