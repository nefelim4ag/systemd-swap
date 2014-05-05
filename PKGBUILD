# Maintainer: Timofey Titovets <Nefelim4ag@gmail.com>
pkgname=systemd-swap
pkgver=2.04
pkgrel=1
pkgdesc="This is script for creating hybrid swap space from zram and swap file. Swap file - auto create dinamic growing swap file and mount it via loop. For enable: sudo systemctl enable systemd-swap. Config in /etc/systemd-swap.cfg"
arch=('any')
url="https://github.com/TimofeyTitovets/systemd-swap"
license=('GPL')
source=(systemd-swap.* README.md)
depends=('systemd')
md5sums=('557131dd52d28f64c8cc188ac3c8b7f9'
         '8ded2e8d30c737a150d2d6d7ff80f0f1'
         '678c2fafed2a32639f33efac96489c9e'
         'e49837b123f89d60e4b106a961096741')
package() {
    install -Dm644 systemd-swap.service $pkgdir/etc/systemd/system/systemd-swap.service
    install -Dm744 systemd-swap.sh $pkgdir/usr/lib/systemd/scripts/systemd-swap.sh
    install -Dm644 systemd-swap.conf $pkgdir/etc/systemd-swap.conf
    cat README.md
}