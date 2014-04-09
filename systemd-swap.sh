#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo Must be called as root!
    exit 1
fi

if [ -f /run/systemd-swap.conf ]; then
    source /run/systemd-swap.conf
else
    if [ -f /etc/systemd-swap.conf ]; then
        source /etc/systemd-swap.conf
        echo
        cp /etc/systemd-swap.conf /run/systemd-swap.conf
    else
        echo config /etc/systemd-swap.conf deleted
        exit 1
    fi
fi

started(){
    if [ -f /run/systemd-swap-started ]; then
        return 1
    else
        return 0
    fi
}

enabled_zram(){
    modprobe zram num_devices=4 || {
        echo zram module does not exist
        zram_size=""
    }
    if [ -z $zram_size ]; then
        echo zram disabled
        return 1
    fi
}

create_zram(){
    size=$(($zram_size/4))
    echo ${size}K > /sys/block/zram0/disksize
    echo ${size}K > /sys/block/zram1/disksize
    echo ${size}K > /sys/block/zram2/disksize
    echo ${size}K > /sys/block/zram3/disksize

    mkswap /dev/zram0
    mkswap /dev/zram1
    mkswap /dev/zram2
    mkswap /dev/zram3

    swapon /dev/zram0 -p 32000
    swapon /dev/zram1 -p 32000
    swapon /dev/zram2 -p 32000
    swapon /dev/zram3 -p 32000
}

deatach_zram(){
    swapoff /dev/zram0
    swapoff /dev/zram1
    swapoff /dev/zram2
    swapoff /dev/zram3

    echo 1 > /sys/block/zram0/reset
    echo 1 > /sys/block/zram1/reset
    echo 1 > /sys/block/zram2/reset
    echo 1 > /sys/block/zram3/reset

    modprobe -r zram
}

enabled_swapf(){
    if [ ! -z $swapf_path ]; then
        touch $swapf_path || {
            echo Path $swapf_path wrong
            swapf_path=""
        }
    fi
    if [ -z $swapf_size ]; then
        return 1
    fi
    if [ -z $swapf_path ]; then
        echo swap file disabled
        return 1
    fi
}

create_swapf(){
    loopdev=$(losetup -f)
    truncate -s $swapf_size $swapf_path
    losetup $loopdev $swapf_path
    mkswap $swapf_path
    swapon $loopdev -p 0
}

deatach_swapf(){
    losetup -d $(losetup | grep $swapf_path | awk '{print $1}')
    swapoff -a
    rm $swapf_path
}

case $1 in
    start)
      started && enabled_zram && create_zram
      started && enabled_swapf&& create_swapf
      touch /run/systemd-swap-started
    ;;

    stop)
      started ||
      enabled_zram && deatach_zram
      enabled_swapf && deatach_swapf
      rm /run/systemd-swap.conf
      rm /run/systemd-swap-started
    ;;
esac