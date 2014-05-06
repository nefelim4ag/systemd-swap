#!/bin/bash -e

# Check if function already has been runned
# $1 - zram || swapf | $2 - work_dir
started(){ [ ! -f "$2/$1" ] # [ ] return 1 or 0 }

# $1 - zram_size | $2 - cpu_count | $3 - work_dir
create_zram(){
    [ -z "$1" ] && echo zram disabled && return 0
    [ -f /dev/zram0 ] || modprobe zram num_devices=$2
    size=$(($1/$2)) tmp=$(($2-1))
    for n in `seq 0 $tmp`
    do
        echo ${size}K > /sys/block/zram$n/disksize
        mkswap -L zram$n /dev/zram$n
        swapon -p 32767 /dev/zram$n
        echo "$n" >> $3/zram
    done
}
# $1 work_dir
deatach_zram(){
    for n in `cat $1/zram`
    do
        swapoff /dev/zram$n
        echo 1 > /sys/block/zram$n/reset
    done
    rm $1/zram
}

# $1 - swapf_size | $2 - swapf_path | $3 - parse_fstab | $4 - work_dir | $5 - reset
create_swapf(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo swap file disabled; return 0
    fi

    # search swap lines
    # grep return 0 only if line exist
    [ "$3" == "1" ] && grep swap /etc/fstab | grep '#' && \
    echo Swap exist in fstab && return 0
    # $1 - swapf_size | $2 - swapf_path
    if [ ! -f "$2" ] || [ ! -z $5 ]; then
        truncate -s "$1" "$2" || return 0
        chmod 0600 "$2"
        mkswap -L loopswap "$2"
    fi

    lpdev=`losetup -f`
    losetup "$lpdev" "$2"
    swapon "$lpdev"
    echo "$lpdev" > "$work_dir/swapf"
}

# $1 - work_dir | $2 - swapf_path | $3 - reset
deatach_swapf(){
    lpdev=`cat "$1/swapf"`
    swapoff "$lpdev"
    losetup -d "$lpdev"  # deatach loop dev
    [ -z "$3" ] || rm "$2" # rm swapfile
    rm "$1/swapf"          # rm started status
}

# $1 - reset | $2 - cpu_count
gen_modprobe(){
    modfile=/etc/modprobe.d/90-systemd-swap.conf
    if [ ! -f "$modfile" ] || [ ! -z "$1" ]; then
        echo options zram num_devices=$2 >  "$modfile"
        echo options loop max_loop=10 max_part=4 >> "$modfile"
    fi
}

################################################################################
# CPU count = Zram devices count
# For parallelize the compression flows
cpu_count=`grep -c ^processor /proc/cpuinfo`
ram_size=`grep MemTotal: /proc/meminfo | awk '{print $2}'`
work_dir=/run/systemd/swap/
################################################################################
backup=$work_dir/systemd-swap.conf
config=/etc/systemd-swap.conf
[ -f "$backup" ] || \
if  [ -f $config ]; then
    mkdir -p $work_dir/
    source "$config"
    [ -z "$swappiness"  ] && echo swappiness=$swappiness   >  "$backup"
    [ -z "$zram_size"   ] && echo zram_size=$zram_size     >> "$backup"
    [ -z "$parse_fstab" ] && echo parse_fstab=$parse_fstab >> "$backup"
    [ -z "$swapf_size"  ] && echo swapf_size=$swapf_size   >> "$backup"
    [ -z "$swapf_path"  ] && echo swapf_path=$swapf_path   >> "$backup"
else
    echo "Config $config deleted, reinstall package"; exit 1
fi
source "$backup"
################################################################################
case $1 in
    start)
        gen_modprobe  "$reset" "$cpu_count" &
        started zram  "$work_dir" && create_zram "$zram_size" "$cpu_count" "$work_dir" &
        started swapf "$work_dir" && create_swapf "$swapf_size" "$swapf_path" "$parse_fstab" "$reset" &
        [ -z "$swappiness" ] || sysctl -w vm.swappiness=$swappiness &
    ;;

    stop)
        started zram  "$work_dir" || deatach_zram  "$work_dir" &
        started swapf "$work_dir" || deatach_swapf "$work_dir" "$swapf_path" "$reset" &
        rm "$backup" & # rm config backup
    ;;
esac