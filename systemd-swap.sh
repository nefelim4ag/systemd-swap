#!/bin/bash -e
# $1 - zram_size | $2 - cpu_count
create_zram(){
    [ -z "$1" ] && echo zram disabled && return 0
    [ -f /dev/zram0 ] || modprobe zram num_devices=$2
    tmp=$(($2-1))
    for n in `seq 0 $tmp`
    do
        echo "$n" >> /run/lock/systemd-swap.zram &
        echo ${1}K > /sys/block/zram$n/disksize
        mkswap /dev/zram$n
        swapon -p 32767 /dev/zram$n              &
    done
}

deatach_zram(){
    for n in `cat /run/lock/systemd-swap.zram`
    do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset         &
    done
    rm "/run/lock/systemd-swap.zram"
}

create_swapf(){
    s=$1 # swap_size=$1
    if [ -z $s ] || [ -z ${swapf_path[0]} ]; then
        echo swap file disabled; return 0
    fi
    for n in ${swapf_path[@]}
    do
        if [ ! -f "$n" ]; then
            truncate -s "$s"   "$n" || return 0
            chmod 0600  "$n"                     &
            mkswap      "$n"
        fi
        lp=`losetup -f`
        losetup $lp $n && swapon $lp             &
        echo $lp >> /run/lock/systemd-swap.swapf  &
    done
}

deatach_swapf(){
    for n in `cat /run/lock/systemd-swap.swapf`
    do
        swapoff "$n" && losetup -d $n            &
    done
    rm /run/lock/systemd-swap.swapf
}

mount_swapdev(){
    [ -z $1 ] && return 0
    for n in $@
    do
        swapon $n
        echo $n > /run/lock/systemd-swap.dev     &
    done
}
unmount_swapdev(){
    for n in `cat /run/lock/systemd-swap.dev`
    do
        swapoff $n                               &
    done
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
    if [ "$parse_fstab" == "1" ] && grep swap /etc/fstab; then
        if grep swap /etc/fstab | grep '#'; then
                :
            else
                unset swapf_size swapf_path swap_devs
                echo Swap already specified in fstab
        fi
    fi
    if [ "$swap_devs" == "1" ]; then
        unset swap_devs
        for n in `blkid -o device`;
        do
            export `blkid -o export $n`
            if [ "$TYPE" == "swap" ]; then
                if swapon -p 0 $DEVNAME; then
                    swap_dev=(${swap_dev[@]} $DEVNAME)
                else
                   :
                fi
            fi
        done
        if [ "$devs_off_swapf" == "1" ]; then
            [ -z ${swap_dev[0]} ] || unset swapf_size swapf_path
        fi
    fi
    if [ ! -z $zram_size ] && [ ! -z $cpu_count ]; then
        zram_size=$(($zram_size/$cpu_count))
    fi
    [ -z $cpu_count       ] || echo cpu_count=$cpu_count   >  $cached
    [ -z $swappiness      ] || echo swappiness=$swappiness >> $cached &
    [ -z $zram_size       ] || echo zram_size=$zram_size   >> $cached &
    [ -z $swapf_size      ] || echo swapf_size=$swapf_size >> $cached &
    [ -z ${swapf_path[0]} ] || \
          echo export "swapf_path=(${swapf_path[@]})" >> $cached &
    [ -z ${swap_devs[0]}  ] || \
          echo export "swap_dev=(${swap_dev[@]})"     >> $cached &
    if [ ! -f "$modfile" ]; then
        echo options zram num_devices=$cpu_count >  $modfile
        echo options loop max_loop=10 max_part=4 >> $modfile
    fi
else
    echo "Config $config deleted, reinstall package"; exit 1
fi
wait && . "$cached"
################################################################################
started(){                     # $1=(zram || swapf || dev)
    [ -f "/run/lock/systemd-swap.$1" ] # return 1 or 0
}
case $1 in
    start)
        started dev   || mount_swapdev $swap_dev                               &
        started zram  || create_zram  $zram_size  $cpu_count                   &
        started swapf || create_swapf $swapf_size                              &
        [ -z $swappiness ] || sysctl -w vm.swappiness=$swappiness
    ;;

    stop|reset)
        started dev   && unmount_swapdev &
        started zram  && deatach_zram    &
        started swapf && deatach_swapf   &
        [ "$1" == "reset" ] && \
            for n in ${swapf_path[@]} $cached $modfile
            do
                [ -f $n ] && rm -v $n &
            done
    ;;
esac
wait