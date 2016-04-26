#!/bin/bash -e
cd "$(dirname $0)"
if [ "$UID" != "0" ]; then
    [ ! -f /usr/bin/sudo ] && echo "Run by root or install sudo!" && exit 1
    sudo cp -v   ./systemd-swap.sh       /usr/lib/systemd/scripts/systemd-swap.sh
    sudo cp -v   ./systemd-swap.conf     /etc/
    sudo ln -svf  /etc/systemd-swap.conf /etc/systemd/swap.conf
    sudo cp -v   ./systemd-swap.service  /etc/systemd/system/systemd-swap.service
    sudo cp -v   ./90-systemd-swap.conf  /etc/modprobe.d/90-systemd-swap.conf
else
    cp -v   ./systemd-swap.sh       /usr/lib/systemd/scripts/systemd-swap.sh
    cp -v   ./systemd-swap.conf     /etc/
    ln -svf  /etc/systemd-swap.conf /etc/systemd/swap.conf
    cp -v   ./systemd-swap.service  /etc/systemd/system/systemd-swap.service
    cp -v   ./90-systemd-swap.conf  /etc/modprobe.d/90-systemd-swap.conf
fi
