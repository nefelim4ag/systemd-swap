## systemd-swap
Script for manage swap on:
* zram - Autoconfigurating
* zswap - configure
* block devices - auto find and do swapon
* files - (sparse files for saving space, support btrfs)
* vram - EXPERIMENTAL: for creating swap on video memory

It is configurable in /etc/systemd-swap.conf.

## Files placed:
```
/etc/systemd-swap.conf
/usr/lib/systemd/system/systemd-swap.service
/usr/lib/systemd/scripts/systemd-swap.sh
```

## Please not forget to enable by:
```
# systemctl enable systemd-swap
```
## Install
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch: in the [community](https://www.archlinux.org/packages/community/any/systemd-swap/).
* Debian: use [package.sh](https://raw.githubusercontent.com/Nefelim4ag/systemd-swap/master/package.sh) in git repo
```
$ git clone https://github.com/Nefelim4ag/systemd-swap.git
$ ./systemd-swap/package.sh debian
$ sudo dpkg -i ././systemd-swap/systemd-swap-*any.deb
```

## Note:
* For zram support: Dependence: util-linux >= 2.26
* If you use zram not for only swap, use kernel 4.2+ or please add rule for modprobe like:
```
options zram max_devices=32
```
* For vram as swap, you need open source drivers [Arch wiki](https://wiki.archlinux.org/index.php/Swap_on_video_ram)
