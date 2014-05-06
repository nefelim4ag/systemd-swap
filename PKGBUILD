# Maintainer: Timofey Titovets <Nefelim4ag@gmail.com>
pkgname=systemd-swap
pkgver=2.10
pkgrel=0
pkgdesc="This is script for creating hybrid swap space from zram and swap file. Swap file - auto create dinamic growing swap file and mount it via loop. For enable: sudo systemctl enable systemd-swap. Config in /etc/systemd-swap.cfg"
arch=('any')
url="https://github.com/TimofeyTitovets/systemd-swap"
license=('GPL')
source=(systemd-swap.* README.md)
depends=('systemd')
md5sums=('9f65d9f7a55ec7cf4c8dea00928ec748'
         'e8a3a477e5d4d4f062bdf8f551faa5fc'
         '66e2e75a27fbcc992e04396cc7902836'
         '948b246d2d6d40b0a0713c4e1cf24bee')

package() {
    install -Dm644 systemd-swap.service $pkgdir/etc/systemd/system/systemd-swap.service
    install -Dm744 systemd-swap.sh $pkgdir/usr/lib/systemd/scripts/systemd-swap.sh
    install -Dm644 systemd-swap.conf $pkgdir/etc/systemd-swap.conf
    cat README.md
}