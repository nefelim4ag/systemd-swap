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
    rm $work_dir/zram
}

create_swapf(){
    modprobe loop max_loop=10 max_part=2
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

    if [ ! -f "$swapf_path" ]; then
        truncate -s "$swapf_size" "$swapf_path" || return 0
        chmod 0600 "$swapf_path"
        mkswap -L loopswap "$swapf_path"
    else
        if [ ! -z $reset ]; then
            truncate -s "$swapf_size" "$swapf_path" || return 0
            chmod 0600 "$swapf_path"
            mkswap -L loopswap "$swapf_path"
        fi
    fi


    loopdev=`losetup -f`
    losetup "$loopdev" "$swapf_path"
    swapon "$loopdev"
    echo "$loopdev" > "$work_dir/swapf"
}

deatach_swapf(){
    loopdev=`cat "$work_dir/swapf"`
    swapoff "$loopdev"
    losetup -d "$loopdev"
    # rm swapfile and started status
    [ ! -z "$reset" ] && rm "$swapf_path"
    rm "$work_dir/swapf"
}

gen_modprobe(){
    modfile=/etc/modprobe.d/90-systemd-swap.conf
    [ ! -z "$reset" ] && rm $modfile
    if [ ! -f "$modfile" ]; then
        cpu_count=`grep -c ^processor /proc/cpuinfo`
        echo options zram num_devices=$cpu_count >  "$modfile"
        echo options loop max_loop=10 max_part=2 >> "$modfile"
    fi
}

case $1 in
    start)
        config_manage start
        gen_modprobe
        started zram  && create_zram
        started swapf && create_swapf
        if [ ! -z "$swappiness" ]; then
            sysctl vm.swappiness=$swappiness
        else
            exit 0
        fi
    ;;

    stop)
        config_manage start
        started zram  || deatach_zram
        started swapf || deatach_swapf
        config_manage stop
    ;;
esac