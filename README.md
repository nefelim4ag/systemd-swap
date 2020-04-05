# systemd-swap

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

## Please don't forget to enable with

```shell
sudo systemctl enable systemd-swap
```

## Install

- <img src="https://www.monitorix.org/imgs/archlinux.png" weight="16" height="16"> **Arch**: in the [community](https://www.archlinux.org/packages/community/any/systemd-swap/).
- <img src="https://www.monitorix.org/imgs/debian.png" weight="16" height="16"> **Debian**: use [package.sh](https://raw.githubusercontent.com/Nefelim4ag/systemd-swap/master/package.sh) in git repo

  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  ./systemd-swap/package.sh debian
  sudo dpkg -i ././systemd-swap/systemd-swap_*_all.deb
  ```

- <img src="https://www.monitorix.org/imgs/fedora.png" weight="16" height="16"> **Fedora**: use [package.sh](https://raw.githubusercontent.com/Nefelim4ag/systemd-swap/master/package.sh)

  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  ./systemd-swap/package.sh fedora f28
  sudo dnf install ./systemd-swap/systemd-swap-*noarch.rpm
  ```

- **Manual**

  ```shell
  git clone https://github.com/Nefelim4ag/systemd-swap.git
  sudo make install
  ```

## About configuration

**Q**: WTF?! Why do you merge swapFC and swapFU?\
**A**: It simplifies testing of swapFC code and makes the code more generic.

**Q**: How can I migrate swapFU config from 3.X to 4.X?\
**A**: Most of the switches are the same, to get configuration like swapFU from swapFC, set `swapfc_max_count` to `1` and `swapfc_chunk_size` to size of swapFU.

**Q**: Do we need to activate both zram and zswap?\
**A**: Nope, it's useless, as zram is a compressed RAM DISK, but zswap is a compressed _"writeback"_ CACHE on swap file/disk.

**Q**: Do I need to use `swapfc_force_use_loop` on swapFC?\
**A**: Nope, as you wish really, native swapfile should work faster and it's safer in OOM condition in comparison to loop backed scenario.

**Q**: When would we want a certain configuration?\
**A**: In most cases (Notebook, Desktop, Server) it's enough to enable zswap + swapfc (on server tuning of swapfc can be needed).
If you use SSD and care about flash memory wear, use only ZRam.

**Q**: Where is the swap file located?\
**A**: Read carefully swap.conf

**Q**: Can we use this to enable hibernation?\
**A**: Nope as hibernation wants a persistent fs blocks and wants access to swap data directly from disk, this will not work on: _zram_, _swapfu_, _swapfc_ (without some magic of course).

## Note

- :information_source: Zram dependence: util-linux >= 2.26
- :information_source: If you use zram not for swap only, use kernel 4.2+ or please add rule for modprobe like:

  ```ini
  options zram max_devices=32
  ```

## Switch On Systemd Swap

- Check your configuration:

  ```shell
  cat /proc/sys/vm/swappiness
  cat /proc/sys/vm/vfs_cache_pressure
  ```

- Recommended configuration for Desktop:

  ```shell
  echo vm.swappiness=5 | sudo tee -a /etc/sysctl.d/99-sysctl.conf
  echo vm.vfs_cache_pressure=50 | sudo tee -a /etc/sysctl.d/99-sysctl.conf
  sudo sysctl -p /etc/sysctl.d/99-sysctl.conf
  ```

- Check configuration after Systemd Swap is installed:

  ```shell
  nano /etc/systemd/swap.conf
  ```

  ```ini
  zram_enabled=0
  zswap_enabled=1
  swapfc_enabled=1
  ```

- Stop your swap:

  ```shell
  sudo swapoff -a
  ```

- Remove swap entry from fstab:

  ```shell
  nano /etc/fstab
  ```

- Remove your swap

  ```shell
  # For Ubuntu
  sudo rm -f /swapfile

  # For Centos 7
  lvremove -Ay /dev/centos/swap
  lvextend -l +100%FREE centos/root
  ```

- Remove swap from Grub:

  ```shell
  # For Ubuntu remove resume* in grub
  nano /etc/default/grub

  # For Centos 7 remove rd.lvm.lv=centos/swap*
  nano /etc/default/grub

  # For Manjaro remove resume* in grub & mkinitcpio
  nano /etc/default/grub
  nano /etc/mkinitcpio.conf
  ```

  ```shell
  # For Ubuntu
  update-grub

  # For Centos 7
  update-grub

  # For Manjaro
  update-grub
  mkinitcpio -P
  ```
