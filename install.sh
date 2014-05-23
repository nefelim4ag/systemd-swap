#!/bin/bash
cd `dirname $0`
sudo cp -v ./systemd-swap.sh      /usr/lib/systemd/scripts/systemd-swap.sh
sudo cp -v ./systemd-swap.conf    /etc/
sudo cp -v ./systemd-swap.service /etc/systemd/system/systemd-swap.service
sudo cp -v ./90-systemd-swap.conf /etc/modprobe.d/90-systemd-swap.conf
