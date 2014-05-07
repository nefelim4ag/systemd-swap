# Maintainer: Timofey Titovets <Nefelim4ag@gmail.com>
pkgname=systemd-swap
pkgver=2.11
pkgrel=0
pkgdesc="This is script for creating hybrid swap space from zram swaps, swap files and swap partitions. Swap file - auto create dinamic growing swap file and mount it via loop. For enable: sudo systemctl enable systemd-swap. Config in /etc/systemd-swap.cfg"
arch=('any')
url="https://github.com/TimofeyTitovets/systemd-swap"
license=('GPL')
source=(systemd-swap.* README.md)
depends=('systemd')
md5sums=('fd9e83f134da2fc313a7a254f4052910'
         'e8a3a477e5d4d4f062bdf8f551faa5fc'
         '9273dde5cb40e735f9a65c0496dbc871'
         '090594a6537c0113a9c75bae929c45f2')

package() {
    install -Dm644 systemd-swap.service $pkgdir/etc/systemd/system/systemd-swap.service
    install -Dm744 systemd-swap.sh      $pkgdir/usr/lib/systemd/scripts/systemd-swap.sh
    install -Dm644 systemd-swap.conf    $pkgdir/etc/systemd-swap.conf
    cat            README.md
}