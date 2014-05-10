#!/bin/bash -e
create_zram(){
    i=$zram_size
    [ -z "$i" ] && echo zram disabled && return 0
    [ -f /dev/zram0 ] || modprobe zram num_devices=$cpu_count
    A=() B=() tmp=$[$cpu_count-1]
    for n in `seq 0 $tmp`; do
        echo ${i}K > /sys/block/zram$n/disksize
        mkswap /dev/zram$n
        B=( ${B[@]} $n )
        A=( ${A[@]} /dev/zram$n )
    done
    echo ${B[@]} > /run/lock/systemd-swap.zram &
    swapon -p 32767 ${A[@]}
}

create_swapf(){
    [ -z ${swapf_path[0]} ] && echo swap file disabled && return 0
    [ -z $swapf_size ]      && echo swap file disabled && return 0
    A=()
    for n in ${swapf_path[@]}; do
        if [ ! -f "$n" ]; then
            truncate -s $swapf_size $n || return 0
            chmod 0600 $n &
            mkswap $n     &
        fi
        lp=`losetup -f`
        A=(${A[@]} $lp)
        losetup $lp $n &
    done
    wait
    swapon ${A[@]} &
    echo ${A[@]} > /run/lock/systemd-swap.swapf
}

mount_swapdev(){
    [ -z ${swap_dev[0]} ] && return 0
    swapon -p 1 ${swap_dev[@]}
    echo ${swap_dev[@]} > /run/lock/systemd-swap.dev
}

deatach_zram(){
    for n in `cat /run/lock/systemd-swap.zram`; do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset &
    done
    rm "/run/lock/systemd-swap.zram"
}

deatach_swapf(){
    A=(`cat /run/lock/systemd-swap.swapf`)
    swapoff ${A[@]}
    losetup -d ${A[@]} &
    rm /run/lock/systemd-swap.swapf
}

unmount_swapdev(){
    A=(`cat /run/lock/systemd-swap.dev`)
    swapoff ${A[@]} &
    rm /run/lock/systemd-swap.dev
}
################################################################################
# Script body
# Cache config generator
cached=/var/tmp/systemd-swap.lock
config=/etc/systemd-swap.conf
modfile=/etc/modprobe.d/90-systemd-swap.conf
[ -f "$cached" ] || \
if  [ -f $config ]; then
    # CPU count = Zram devices count for parallelize the compression flows
    cpu_count=`grep -c ^processor /proc/cpuinfo`
    ram_size=`grep MemTotal: /proc/meminfo | awk '{print $2}'`
    . "$config"
    tmp="`grep swap /etc/fstab || :`"
    if [ ! -z "$parse_fstab" ] && [ ! -z "$tmp" ]; then
        tmp="`echo $tmp | grep '#' || :`"
        if [ ! -z "$tmp" ]; then
            unset swapf_size swapf_path swap_devs tmp
            echo Swap already specified in fstab
        fi
    fi
    if [ ! -z "$swap_devs" ]; then
        for n in `blkid -o device`; do
            export `blkid -o export $n`
            if [ "$TYPE" == "swap" ] && swapon -f -p 1 $DEVNAME; then
                swap_dev=(${swap_dev[@]} $DEVNAME)
                swapoff $DEVNAME &
            fi
        done
        if [ ! -z "$swap_devs_off_swapf" ]; then
            [ -z ${swap_dev[0]} ] || unset swapf_size swapf_path
        fi
    fi
    if [ ! -z $zram_size ] && [ ! -z $cpu_count ]; then
        zram_size=$(($zram_size/$cpu_count))
    fi

    [ -z $cpu_count       ] || A=( ${A[@]} cpu_count=$cpu_count   )
    [ -z $swappiness      ] || A=( ${A[@]} swappiness=$swappiness )
    [ -z $zram_size       ] || A=( ${A[@]} zram_size=$zram_size   )
    [ -z $swapf_size      ] || A=( ${A[@]} swapf_size=$swapf_size )
    [ -z ${swapf_path[0]} ] || A=( ${A[@]} "swapf_path=(${swapf_path[@]})" )
    [ -z ${swap_dev[0]}   ] || A=( ${A[@]} "swap_dev=(${swap_dev[@]})"     )
    echo export ${A[@]} >  $cached

    if [ ! -f "$modfile" ]; then
        echo options zram num_devices=$cpu_count >  $modfile
        echo options loop max_loop=10 max_part=4 >> $modfile
    fi
else
    echo "Config $config deleted, reinstall package"; exit 1
fi
. "$cached"
################################################################################
start(){ # $1=(zram || swapf || dev)
    [ -f "/run/lock/systemd-swap.$1" ] # return 1 or 0
}
case $1 in
    start)
        [ -z $swappiness ] || sysctl -w vm.swappiness=$swappiness &
        start zram  || create_zram   &
        start dev   || mount_swapdev &
        start swapf || create_swapf
    ;;
    stop)
        start zram  && deatach_zram    &
        start dev   && unmount_swapdev &
        start swapf && deatach_swapf
    ;;
    reset)
        $0 stop
        for n in ${swapf_path[@]} $cached $modfile
        do
            [ -f $n ] && rm -v $n
        done
        $0 start
    ;;
esac