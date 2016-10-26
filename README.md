## systemd-swap
Script for manage swap on:
* zswap - Enable/Configure
* zram - Autoconfigurating
* files - (sparse files for saving space, support btrfs)
* block devices - auto find and do swapon

It is configurable in /etc/systemd/swap.conf.

## Files placed:
```
/etc/systemd/swap.conf
/usr/lib/systemd/system/systemd-swap.service
/usr/bin/systemd-swap
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
