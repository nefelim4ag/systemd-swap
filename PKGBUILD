# Maintainer: Timofey Titovets <Nefelim4ag@gmail.com>
pkgname=systemd-swap
pkgver=2.05
pkgrel=1
pkgdesc="This is script for creating hybrid swap space from zram and swap file. Swap file - auto create dinamic growing swap file and mount it via loop. For enable: sudo systemctl enable systemd-swap. Config in /etc/systemd-swap.cfg"
arch=('any')
url="https://github.com/TimofeyTitovets/systemd-swap"
license=('GPL')
source=(systemd-swap.* README.md)
depends=('systemd')
md5sums=('de47f112ad443e7e70c00327276e2352'
         '8ded2e8d30c737a150d2d6d7ff80f0f1'
         '60b0b9430afbc0ec169e9e8c2dcb3e8b'
         'f34332367165b34fb59bcd725604eb5f')

package() {
    install -Dm644 systemd-swap.service $pkgdir/etc/systemd/system/systemd-swap.service
    install -Dm744 systemd-swap.sh $pkgdir/usr/lib/systemd/scripts/systemd-swap.sh
    install -Dm644 systemd-swap.conf $pkgdir/etc/systemd-swap.conf
    cat README.md
}