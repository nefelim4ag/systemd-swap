#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo Must be called as root!
    exit 1
fi

# Backup config
if [ -f /run/systemd/swap/swap.conf ]; then
    source /run/systemd/swap/swap.conf
else
    if [ -f /etc/systemd-swap.conf ]; then
        source /etc/systemd-swap.conf
        mkdir -p /run/systemd/swap/
        cp /etc/systemd-swap.conf /run/systemd/swap/swap.conf
    else
        echo config /etc/systemd-swap.conf deleted
        exit 1
    fi
fi

# Check if function already be called
started(){
    mkdir -p /run/systemd/swap/
    if [ -f /run/systemd/swap/$1 ]; then
        return 1
    else
        return 0
    fi
}

# ZRam part
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
    cpu_count=$(grep -c ^processor /proc/cpuinfo)
    size=$(($zram_size/$cpu_count))
    n=0
    while [[ $n < $cpu_count ]]
    do
        echo ${size}K > /sys/block/zram${n}/disksize
        mkswap /dev/zram${n}
        swapon /dev/zram${n} -p 32000
        n=$(($n+1))
    done
    touch /run/systemd/swap/zram
}

deatach_zram(){
    cpu_count=$(grep -c ^processor /proc/cpuinfo)
    n=0
    while [[ $n < $cpu_count ]]
    do
        swapoff /dev/zram${n}
        echo 1 > /sys/block/zram${n}/reset
        n=$(($n+1))
    done
    modprobe -r zram
    rm /run/systemd/swap/zram
}

enabled_swapf(){
    modprobe loop || {
        echo loop module does not exist
        swapf_path=""
        swapf_size=""
    }
    if [ ! -z $swapf_path ]; then
        touch $swapf_path || {
            echo Path $swapf_path wrong
            swapf_path=""
            swapf_size=""
        }
    fi
    if [ -z $swapf_size ]; then
        echo swap file disabled
        return 1
    fi
    if [ -z $swapf_path ]; then
        echo swap file disabled
        return 1
    fi
}

create_swapf(){
    truncate -s $swapf_size $swapf_path
    chmod 0600 $swapf_path
    mkswap $swapf_path
    swapon $swapf_path -p 0 || {
        loopdev=$(losetup -f)
        losetup $loopdev $swapf_path
        swapon $loopdev -p 0
    }
    touch /run/systemd/swap/swapf
}

deatach_swapf(){
    loopdev=$(swapon -s | grep loop | awk '{print $1}' | tail -n 1)
    while [ ! -z $loopdev ]
    do
        swapoff $loopdev
        losetup -d $loopdev
        loopdev=$(swapon -s | grep loop | awk '{print $1}' | tail -n 1)
    done
    swapf_directly=$(swapon -s | grep $swapf_path | awk '{print $1}' | tail -n 1 )
    [ ! -z $swapf_directly ] && swapoff $swapf_path
    rm $swapf_path
    rm /run/systemd/swap/swapf
}

case $1 in
    start)
      started zram  && enabled_zram  && create_zram
      started swapf && enabled_swapf && create_swapf
    ;;

    stop)
      started zram  || enabled_zram  && deatach_zram
      started swapf || enabled_swapf && deatach_swapf
      rm /run/systemd/swap/swap.conf
    ;;
esac