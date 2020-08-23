# systemd-swap
[![Code Style: Black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/ambv/black)

Script to manage swap on:

- [zswap](https://www.kernel.org/doc/Documentation/vm/zswap.txt) - Enable/Configure
- [zram](https://www.kernel.org/doc/Documentation/blockdev/zram.txt) - Autoconfigurating for swap
- files - (sparse files for saving space, supports btrfs)
- block devices - auto find and do swapon

:information_source: It is configurable in `/etc/systemd/swap.conf`.

Additional terms:

- **SwapFC** (File Chunked) - provides a dynamic swap file allocation/deallocation

## File location

```text
/etc/systemd/swap.conf
/usr/lib/systemd/system/systemd-swap.service
/usr/bin/systemd-swap
```

## Please don't forget to enable and start with

```shell
sudo systemctl enable --now systemd-swap
```

## Install

- <img src="https://www.monitorix.org/imgs/archlinux.png" weight="16" height="16"> **Arch Linux**: in the [community](https://www.archlinux.org/packages/community/any/systemd-swap/) repo.

- <img src="https://www.monitorix.org/imgs/debian.png" weight="16" height="16"> **Debian based distros**

  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  cd systemd-swap
  make deb
  sudo apt install ./systemd-swap_*_all.deb
  ```

- <img src="https://www.monitorix.org/imgs/fedora.png" weight="16" height="16"> **Fedora based distros**

  ```shell
  sudo dnf copr enable zeno/systemd-swap
  sudo dnf install systemd-swap
  ```
  
  or
  
  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  cd systemd-swap
  make rpm
  sudo dnf install ./systemd-swap-*noarch.rpm

- **Manual**

  Install dependencies:
  - `python3` >= 3.7
  - `python3` packages: `systemd` and `sysv_ipc`

  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  cd systemd-swap
  sudo make install

  # or into /usr/local:
  sudo make prefix=/usr/local install
  ```

## About configuration

**Q**: Do we need to activate both zram and zswap?\
**A**: Nope, it's useless, as zram is a compressed RAM DISK, but zswap is a compressed _"writeback"_ CACHE on swap file/disk. Also having both activated can lead to inverse LRU as noted [here](https://askubuntu.com/questions/471912/zram-vs-zswap-vs-zcache-ultimate-guide-when-to-use-which-one/472227#472227)

**Q**: Do I need to use `swapfc_force_use_loop` on swapFC?\
**A**: Nope, as you wish really, native swapfile should work faster and it's safer in OOM condition in comparison to loop backed scenario.

**Q**: When would we want a certain configuration?\
**A**: In most cases (Notebook, Desktop, Server) it's enough to enable zswap + swapfc (on server tuning of swapfc can be needed). If you use a SSD and care about flash memory wear, use only ZRam.

**Q**: Can we use this to enable hibernation?\
**A**: Nope as hibernation wants a persistent fs blocks and wants access to swap data directly from disk, this will not work on: _swapfc_ (without some magic of course, see [#85](https://github.com/Nefelim4ag/systemd-swap/issues/85)).

## Note

- :information_source: Zram dependence: util-linux >= 2.26
- :information_source: If you use zram not for swap only, use kernel 4.2+ or please add rule for modprobe like:

  ```ini
  options zram max_devices=32
  ```

## Switch on systemd-swap:s automatic swap management

- Enable swapfc if wanted (note, you should **never** use zram and zswap at the same time)

  ```shell
  vim /etc/systemd/swap.conf.d/overrides.conf
  ```

  ```ini
  swapfc_enabled=1
  ```

- Stop any external swap:

  ```shell
  sudo swapoff -a
  ```

- Remove swap entry from fstab:

  ```shell
  vim /etc/fstab
  ```

- Remove your swap

  ```shell
  # For Ubuntu
  sudo rm -f /swapfile

  # For Centos 7 (if using a swap partition and lvm)
  lvremove -Ay /dev/centos/swap
  lvextend -l +100%FREE centos/root
  ```

- Remove swap from Grub:

  ```shell
  # For Ubuntu remove resume* in grub
  vim /etc/default/grub

  # For Centos 7 remove rd.lvm.lv=centos/swap*
  vim /etc/default/grub

  # For Manjaro remove resume* in grub & mkinitcpio
  vim /etc/default/grub
  vim /etc/mkinitcpio.conf
  ```

  ```shell
  # For Ubuntu
  update-grub

  # For Centos 7
  grub2-mkconfig -o /boot/grub2/grub.cfg

  # For Manjaro
  update-grub
  mkinitcpio -P
  ```
