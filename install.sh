#!/bin/bash -e
################################################################################
# echo wrappers
INFO(){ echo -n "INFO: "; echo "$@" ;}
WARN(){ echo -n "WARN: "; echo "$@" ;}
ERRO(){ echo -n "ERRO: "; echo -n "$@" ; echo " Abort!"; exit 1;}

cd "$(dirname $0)"
if [ "$UID" != "0" ]; then
    [ ! -f /usr/bin/sudo ] && ERRO "Run by root or install sudo!" || :
    SUDO=sudo
else
    unset SUDO
fi

if [ -f /etc/systemd-swap.conf ]; then
    INFO "File /etc/systemd-swap.conf already exists"
    if cmp -s ./systemd-swap.conf /etc/systemd-swap.conf; then
        :
    else
        INFO "New config saved as /etc/systemd-swap.conf.new"
        $SUDO cp -v ./systemd-swap.conf /etc/systemd-swap.conf.new
    fi
else
    $SUDO cp -v ./systemd-swap.conf /etc/systemd-swap.conf
fi

$SUDO cp -v   ./systemd-swap.sh       /usr/lib/systemd/scripts/systemd-swap.sh
$SUDO ln -svf  /etc/systemd-swap.conf /etc/systemd/swap.conf
$SUDO cp -v   ./systemd-swap.service  /usr/lib/systemd/system/systemd-swap.service
