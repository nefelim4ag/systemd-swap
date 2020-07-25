#!/usr/bin/env bash

set -eo pipefail

# echo wrappers
INFO(){ echo -n "INFO: "; echo "$@" ;}
WARN(){ echo -n "WARN: "; echo "$@" ;}
ERRO(){ echo -n "ERRO: "; echo -n "$@" ; echo " Abort!"; exit 1;}

get_version(){
  VERSION=$(git describe --abbrev=0 --tags)
  [ -z "${VERSION}" ] && ERRO "Can't get git tag, VERSION is empty!"
  return 0
}

debian_package(){
  cd "$(dirname "$0")"
  get_version
  DEB_NAME="systemd-swap_${VERSION}_all"
  rm -rf "${DEB_NAME}"
  mkdir -p "${DEB_NAME}"
  DESTDIR="${DEB_NAME}"/ make install
  mkdir -p  "${DEB_NAME}/DEBIAN"
  chmod 755 "${DEB_NAME}/DEBIAN"
  {
    echo "Package: systemd-swap"
    echo "Version: ${VERSION}"
    echo "Section: custom"
    echo "Priority: optional"
    echo "Architecture: all"
    echo "Depends: util-linux"
    echo "Essential: no"
    echo "Installed-Size: 16"
    echo "Maintainer: nefelim4ag@gmail.com"
    echo "Description: Script for creating hybrid swap space from zram swaps, swap files and swap partitions."
    echo "Rules-Requires-Root: no"
  } > "${DEB_NAME}/DEBIAN/control"
  pushd "${DEB_NAME}"
  find etc/ -type f -exec echo /{} \; > "DEBIAN/conffiles"
  popd
  dpkg-deb --build --root-owner-group "${DEB_NAME}"
  rm -rf "${DEB_NAME}"
}

archlinux_package(){
  INFO "Use pacman -S systemd-swap"
}

centos_package(){
  cd "$(dirname "$0")"
  get_version
  test -d ./build && rm -rf ./build
  mkdir -p ./build/BUILD
  find . -type f ! -path './.git/*' ! -path './build/*' -exec cp {} build/BUILD \;
  rpmbuild --define "_topdir $(pwd)/build" -bb systemd-swap.spec
  mv build/RPMS/noarch/*.rpm ./
  rm -rf ./build
}

fedora_package(){
  cd "$(dirname "$0")"
  FEDORA_VERSION=$1
  get_version
  [ -z "${FEDORA_VERSION}" ] && ERRO "Please specify fedora version e.g.: $0 fedora f28"
  fedpkg --release "${FEDORA_VERSION}" local
  mv noarch/*.rpm ./
  rmdir noarch
  rm ./*.src.rpm
}

case $1 in
  debian)
    debian_package
  ;;
  archlinux)
    archlinux_package
  ;;
  fedora)
    fedora_package "$2"
  ;;
  centos)
    centos_package
  ;;
  *)
    echo "$0 <debian|archlinux|fedora [version]>|centos"
  ;;
esac
