# Maintainer: Timofey Titovets <Nefelim4ag@gmail.com>
pkgname=systemd-swap
pkgver=2.14
pkgrel=2
pkgdesc="This is script for creating hybrid swap space from zram swaps, swap files and swap partitions. Swap file - auto create dinamic growing swap file and mount it via loop. For enable: sudo systemctl enable systemd-swap. Config in /etc/systemd-swap.cfg"
arch=('any')
url="https://github.com/TimofeyTitovets/systemd-swap"
license=('GPL3')
conflicts=(systemd-loop-swapfile autoswap zramswap zram)
replaces=(systemd-loop-swapfile-auto)
source=(systemd-swap.service systemd-swap.sh systemd-swap.conf README.md CHANGELOG.md)
depends=('systemd')
md5sums=('ce2bd0e957429d5a5e58404b60ce5321'
         'c5dce27430d955d99653373122bcf473'
         '8d55c3830dafd90fa1398119ad3de4d2'
         '090594a6537c0113a9c75bae929c45f2'
         'f78ebe3f43aa843017fdca4066988fae')

package() {
    install -Dm644 systemd-swap.service $pkgdir/etc/systemd/system/systemd-swap.service
    install -Dm744 systemd-swap.sh      $pkgdir/usr/lib/systemd/scripts/systemd-swap.sh
    install -Dm644 systemd-swap.conf    $pkgdir/etc/systemd-swap.conf
    cat README.md
}