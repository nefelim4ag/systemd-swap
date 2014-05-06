#!/bin/bash -e
# $1 - zram_size | $2 - cpu_count
create_zram(){
    [ -z "$1" ] && echo zram disabled && return 0
    [ -f /dev/zram0 ] || modprobe zram num_devices=$2
    tmp=$(($2-1))
    for n in `seq 0 $tmp`
    do
        echo "$n" >> "/run/lock/systemd-swap.zram"  &
        echo ${1}K > /sys/block/zram$n/disksize
        mkswap /dev/zram$n
        swapon -p 32767  /dev/zram$n                &
    done
}

deatach_zram(){
    for n in `cat /run/lock/systemd-swap.zram`
    do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset            &
    done
    rm "/run/lock/systemd-swap.zram"
}

create_swapf(){
    # swapf_size=$1 swapf_path=$2
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo swap file disabled; return 0
    fi

    if [ ! -f "$2" ]; then
        truncate -s "$1"   "$2" || return 0
        chmod 0600  "$2"                           &
        mkswap "$2"
    fi

    lpdev=`losetup -f`
    losetup "$lpdev" "$2" && swapon "$lpdev"       &
    echo "$lpdev" > "/run/lock/systemd-swap.swapf" &
}

deatach_swapf(){
    lpdev=`cat "/run/lock/systemd-swap.swapf"`
    swapoff "$lpdev" && losetup -d "$lpdev"        &
    rm "/run/lock/systemd-swap.swapf"              &
}

################################################################################
# Script body
# Cache config generator
cached=/var/tmp/systemd-swap.lock
config=/etc/systemd-swap.conf
[ -f "$cached" ] || \
if  [ -f $config ]; then
    # CPU count = Zram devices count for parallelize the compression flows
    cpu_count=`grep -c ^processor /proc/cpuinfo`
    ram_size=`grep MemTotal: /proc/meminfo | awk '{print $2}'`
    modfile=/etc/modprobe.d/90-systemd-swap.conf

    . "$config"

    if [ "$parse_fstab" == "1" ] && grep swap /etc/fstab | grep '#'; then
        unset swapf_size swapf_path parse_fstab
        echo Swap already specified in fstab
    fi

    [ -z "$cpu_count"   ] || echo cpu_count=$cpu_count   >  "$cached"
    [ -z "$swappiness"  ] || echo swappiness=$swappiness >> "$cached"  &
           zram_size=$(($zram_size/$cpu_count))
    [ -z "$zram_size"   ] || echo zram_size=$zram_size   >> "$cached"  &
    [ -z "$swapf_size"  ] || echo swapf_size=$swapf_size >> "$cached"  &
    [ -z "$swapf_path"  ] || echo swapf_path=$swapf_path >> "$cached"  &
    if [ ! -f "$modfile" ]; then
        echo options zram num_devices=$cpu_count         >  "$modfile"
        echo options loop max_loop=10 max_part=4         >> "$modfile"
    fi
else
    echo "Config $config deleted, reinstall package"; exit 1
fi
wait && . "$cached"
################################################################################
started(){                     # $1=(zram || swapf)
    [ -f "/run/lock/systemd-swap.$1" ] # return 1 or 0
}
case $1 in
    start)
        started zram  || create_zram  "$zram_size"  "$cpu_count"    &
        started swapf || create_swapf "$swapf_size" "$swapf_path"   &
        [ -z "$swappiness" ] || sysctl -w vm.swappiness=$swappiness &
    ;;

    stop)
        started zram  && deatach_zram  &
        started swapf && deatach_swapf &
    ;;
    reset)
        started zram  && deatach_zram  &
        started swapf && deatach_swapf &
        rm -v $swapf_path $cached /etc/modprobe.d/90-systemd-swap.conf
    ;;
esac
wait