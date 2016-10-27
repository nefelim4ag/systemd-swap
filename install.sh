#!/bin/bash -e
################################################################################
# echo wrappers
INFO(){ echo -n "INFO: "; echo "$@" ;}
WARN(){ echo -n "WARN: "; echo "$@" ;}
ERRO(){ echo -n "ERRO: "; echo -n "$@" ; echo " Abort!"; exit 1;}

PREFIX="/"
case $1 in
    PREFIX=*) PREFIX="${1//PREFIX=/}";;
esac

cd "$(dirname $0)"
if [ "$PREFIX" == "/" ]; then
    if [ "$UID" != "0" ]; then
        [ ! -f /usr/bin/sudo ] && ERRO "Run by root or install sudo!" || :
        SUDO=sudo
    else
        unset SUDO
    fi
fi

$SUDO mkdir -p $PREFIX/etc/systemd/
if [ -f $PREFIX/etc/systemd/swap.conf ]; then
    INFO "File $PREFIX/etc/systemd/swap.conf already exists"
    if cmp -s ./systemd/swap.conf $PREFIX/etc/systemd/swap.conf; then
        :
    else
        INFO "New config saved as $PREFIX/etc/systemd/swap.conf.new"
        $SUDO install -Dm 644 ./swap.conf $PREFIX/etc/systemd/swap.conf.new
    fi
else
    $SUDO install -Dm 644 ./swap.conf $PREFIX/etc/systemd/swap.conf
fi

$SUDO install -Dm755   ./systemd-swap $PREFIX/usr/bin/systemd-swap
$SUDO install -Dm644 ./systemd-swap.service  $PREFIX/usr/lib/systemd/system/systemd-swap.service
