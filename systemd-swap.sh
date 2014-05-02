#!/bin/bash -e

# CPU count = Zram devices count
# For parallelize the compression flows
cpu_count=`grep -c ^processor /proc/cpuinfo`
ram_size=`grep MemTotal: /proc/meminfo | awk '{print $2}'`
work_dir=/run/systemd/swap/

config_manage() {
    backup=$work_dir/swap.conf
    config=/etc/systemd-swap.conf
    case $1 in
        start)
            # Backup config
            if [ ! -f "$backup" ]; then
                if [ -f $config ]; then
                      mkdir -p $work_dir/
                      cp $config "$backup"
                else
                      echo "Config $config deleted, reinstall package"
                      exit 1
                fi
            fi
            source "$backup"
        ;;

        stop) rm "$backup" ;;
    esac
}

# Check if function already has been caused
started(){
    if [ -f "$work_dir/$1" ]; then
        return 1
    else
        return 0
    fi
}

create_zram(){
    if [ -z "$zram_size" ]; then
        echo zram disabled
        return 1
    fi

    modprobe zram num_devices=$cpu_count
    size=$(($zram_size/$cpu_count))
    cpu_count=$(($cpu_count-1))
    for n in `seq 0 $cpu_count`
    do
        echo ${size}K > /sys/block/zram$n/disksize
        mkswap -L zram$n /dev/zram$n
        swapon -p 32767 /dev/zram$n
        echo "$n" >> $work_dir/zram
    done
}

deatach_zram(){
    for n in `cat $work_dir/zram`
    do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset
    done
    modprobe -r zram
    rm $work_dir/zram
}

create_swapf(){
    modprobe loop
    if [ "$swapf_parse_fstab" == "1" ]; then
        # search swap lines
        # grep return 1 if line not found
        swap_string=`grep swap /etc/fstab || :`
        if [ ! -z "$swap_string" ]; then
            # check, swap lines commented?
            swap_string_not_commented=`echo $swap_string | grep '#' || :`
            # if line exist and not commented - disable swapf
            if [ -z "$swap_string_not_commented" ]; then
                echo swap exist in fstab
                return 0
            fi
        fi
    fi

    if [ -z "$swapf_size" ] || [ -z "$swapf_path" ]; then
        echo swap file disabled
        return 0
    fi

    truncate -s $swapf_size $swapf_path || return 0
    chmod 0600 $swapf_path
    mkswap -L loopswap $swapf_path
    loopdev=`losetup -f`
    losetup $loopdev $swapf_path
    swapon $loopdev
    echo $loopdev >> $work_dir/swapf
}

deatach_swapf(){
    for loopdev in `cat $work_dir/swapf`
    do
        swapoff $loopdev
        losetup -d $loopdev
    done
    # rm swapfile and started status
    rm $swapf_path $work_dir/swapf
}

set_swappiness(){
    if [ ! -z "$swappiness" ]; then
        sysctl vm.swappiness=$swappiness
    else
        return 0
    fi
}

case $1 in
    start)
        config_manage start
        started zram  && create_zram
        started swapf && create_swapf
        set_swappiness
    ;;

    stop)
        config_manage start
        started zram  || deatach_zram
        started swapf || deatach_swapf
        config_manage stop
    ;;
esac