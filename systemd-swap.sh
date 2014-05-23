#!/bin/bash -e

manage_zram(){
  case $1 in
      start)
          [ -z "$zram_size" ] && return 0
          [ -f /dev/zram0   ] || modprobe zram num_devices=32
          zram_size=$[$zram_size/$zram_num_devices]
          A=() B=() tmp=$[$zram_num_devices-1]
          for n in `seq 0 $tmp`; do
              echo ${zram_size}K > /sys/block/zram$n/disksize && \
              mkswap /dev/zram$n && \
              B=( ${B[@]} $n ) && A=( ${A[@]} /dev/zram$n )
          done
          echo ${B[@]} > /run/lock/systemd-swap.zram &
          swapon -p 32767 ${A[@]}
      ;;
      stop)
          for n in `cat /run/lock/systemd-swap.zram`; do
              swapoff /dev/zram$n
              echo 1 > /sys/block/zram$n/reset &
          done
          rm /run/lock/systemd-swap.zram
      ;;
  esac
}

manage_swapf(){
  case $1 in
      start)
          [[ -z ${swapf_path[0]} || -z $swapf_size ]] && return 0
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
          wait && swapon ${A[@]}
          echo ${A[@]} > /run/lock/systemd-swap.swapf
      ;;
      stop)
          A=(`cat /run/lock/systemd-swap.swapf`)
          [ -z ${A[@]} ] || swapoff ${A[@]}
          [ -z ${A[@]} ] || losetup -d ${A[@]}
          rm /run/lock/systemd-swap.swapf
      ;;
  esac
}

manage_swapdev(){
  case $1 in
      start)
          [ -z ${swap_dev[0]} ] && return 0
          swapon -p 1 ${swap_dev[@]} || :
          echo ${swap_dev[@]} > /run/lock/systemd-swap.dev
      ;;
      stop)
          A=(`cat /run/lock/systemd-swap.dev`)
          [ -z ${A[@]} ] || swapoff ${A[@]} || :
          rm /run/lock/systemd-swap.dev
      ;;
  esac
}

################################################################################
# Script body
config=/etc/systemd-swap.conf
cached_config=/var/tmp/systemd-swap.cache

parse_config(){
    cpu_count=`grep -c ^processor /proc/cpuinfo`
    ram_size=`awk '/MemTotal:/ { print $2 }' /proc/meminfo`

    . "$config"
    [ -z $zram_num_devices ] && zram_num_devices=$cpu_count

    [ -z "$parse_fstab"  ] || tmp=`grep '^[^#]*swap' /etc/fstab`
    if [ ! -z "$tmp" ]; then
        unset swapf_size swapf_path parse_devs tmp
        echo Swap already specified in fstab
    fi

    swap_dev=( ${swap_partitions[@]} )
    if [ ! -z "$parse_devs" ]; then
        for n in `blkid -o device`; do
            export `blkid -o export $n`
            if [ "$TYPE" == "swap" ] && swapon -f -p 1 $DEVNAME; then
                swap_dev=(${swap_dev[@]} $DEVNAME)
                swapoff $DEVNAME
            fi
        done

        if [ ! -z "$parse_devs_off_swapf" ]; then
            [ -z ${swap_dev[0]} ] || unset swapf_size swapf_path
        fi
    fi

    [ -z  $parse_zswap ] || zswap=(`dmesg | grep "loading zswap" || true`)
    [ -z "$zswap" ] || unset zram_size cpu_count zswap
}

handle_cache(){
    [ -z $cpu_count       ] || A=( ${A[@]} zram_num_devices=$zram_num_devices )
    [ -z $zram_size       ] || A=( ${A[@]} zram_size=$zram_size               )
    [ -z $swapf_size      ] || A=( ${A[@]} swapf_size=$swapf_size             )
    [ -z ${swapf_path[0]} ] || A=( ${A[@]} "swapf_path=( ${swapf_path[@]} )"  )
    [ -z ${swap_dev[0]}   ] || A=( ${A[@]} "swap_dev=( ${swap_dev[@]} )"      )
    if [ -z ${A[0]} ]; then
        touch $cached_config
    else
        echo "export ${A[@]}" >  $cached_config
    fi
}

if [ -f $cached_config ]; then
    . $cached_config
else
    if  [ -f $config ]; then
        parse_config
        [ -z $cache ] || handle_cache
    else
        echo "Config $config deleted, reinstall package"; exit 1
    fi
fi

################################################################################
start(){ # $1=(zram || swapf || dev)
    [ -f "/run/lock/systemd-swap.$1" ] # return 1 or 0
}

case $1 in
    start)
        start zram  || manage_zram    $1
        start dev   || manage_swapdev $1
        start swapf || manage_swapf   $1
    ;;
    stop)
        start zram  && manage_zram    $1
        start dev   && manage_swapdev $1
        start swapf && manage_swapf   $1
    ;;
    reset)
        #stoping
        start zram  && manage_zram    $1
        start dev   && manage_swapdev $1
        start swapf && manage_swapf   $1
        for n in ${swapf_path[@]} $cached_config; do
            [ -f $n ] && rm -v $n
        done
        $0 start || :
    ;;
esac
wait
