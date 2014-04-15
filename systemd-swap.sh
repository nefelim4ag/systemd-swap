#!/bin/bash -e

[[ $EUID -ne 0 ]] && echo Must be called as root! && exit 1

#CPU count = Zram devices count
cpu_count=$(grep -c ^processor /proc/cpuinfo)
ram_size=$(grep MemTotal: /proc/meminfo | awk '{print $2}')

config_manage() {
    run_backup=/run/systemd/swap/swap.conf
    config=/etc/systemd-swap.conf
    case $1 in
        start)
            # Backup config
            if [ ! -f "$run_backup" ]; then
                if [ -f /etc/systemd-swap.conf ]; then
                      mkdir -p /run/systemd/swap/
                      cp $config "$run_backup"
                else
                      echo "Config $config deleted, reinstall package"
                      exit 1
                fi
            fi
            source "$run_backup"
        ;;

        stop) rm "$run_backup" ;;
    esac
}

# Check if function already be called
started(){
    if [ -f "/run/systemd/swap/$1" ]; then
        return 1
    else
        return 0
    fi
}

# ZRam part
test_zram(){
    [ -z "$zram_size" ] && echo zram disabled && return 1
    [ ! -z "$zram_size" ] && return 0
}

create_zram(){
    modprobe zram num_devices=$cpu_count
    size=$(($zram_size/$cpu_count))
    cpu_count=$(($cpu_count-1))
    for n in `seq 0 $cpu_count`
    do
        echo ${size}K > /sys/block/zram$n/disksize
        mkswap /dev/zram$n
        swapon -p 32000 /dev/zram$n
    done
    touch /run/systemd/swap/zram
}

deatach_zram(){
    cpu_count=$(($cpu_count-1))
    for n in `seq 0 $cpu_count`
    do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset
    done
    modprobe -r zram
    rm /run/systemd/swap/zram
}

test_swapf(){
    modprobe loop
    if [[ "$swapf_parse_fstab" == "1" ]]; then
        swap_string="$(grep swap /etc/fstab)" # search swap lines
        swap_string_not_commented="$(echo $swap_string | grep '#')" # check, swap lines commented?
        # if line exist and not commented - disable swapf
        [ -z "$swap_string_not_commented" ] && [ ! -z "$swap_string" ] && \
        echo swap exist in fstab && return 1
    fi
    touch "$swapf_path" &> /dev/null || {
            echo Path $swapf_path wrong
            return 1
        }
    if [ -z "$swapf_size" ] || [ -z "$swapf_path" ]; then
        echo swap file disabled
        return 1
    fi
}

create_swapf(){
    truncate -s $swapf_size $swapf_path
    chmod 0600 $swapf_path
    mkswap $swapf_path
    loopdev=$(losetup -f)
    losetup $loopdev $swapf_path
    swapon $loopdev
    touch /run/systemd/swap/swapf
}

deatach_swapf(){
    for loopdev in `grep loop /proc/swaps | awk '{print $1}'`
    do
        swapoff $loopdev
        losetup -d $loopdev
    done
    rm $swapf_path /run/systemd/swap/swapf
}

set_swappiness(){
    [ ! -z "$swappiness" ] && sysctl vm.swappiness=$swappiness
}

case $1 in
    start)
        config_manage start
        started zram  && test_zram  && create_zram
        started swapf && test_swapf && create_swapf
        set_swappiness
    ;;

    stop)
        config_manage start
        started zram  || deatach_zram
        started swapf || deatach_swapf
        config_manage stop
    ;;
esac