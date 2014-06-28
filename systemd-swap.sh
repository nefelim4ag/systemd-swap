#!/bin/bash -e

write(){
    [ "$#" != "2" ] && return 0
    val=$1 file=$2
    echo $val | tee $file
}

manage_zram(){
  case $1 in
      start)
          [ -z "$zram_size" ] && return 0
          [ -f /dev/zram0   ] || modprobe zram num_devices=32
          if [ ! -z $zram_compress ]; then
              [ -f /sys/block/zram0/comp_algorithm ] || unset zram_compress
          fi
          # Find and use first free device
          for i in `seq 0 32`; do
              if [ `cat /sys/block/zram$i/disksize` == "0" ]; then
                  dev=zram$i
                  sys=/sys/block/$dev
                  write $zram_compress $sys/comp_algorithm
                  write $zram_streams  $sys/max_comp_streams
                  write $zram_size     $sys/disksize
                  mkswap /dev/$dev
                  swapon -p 32767 /dev/$dev
                  write "dev=$dev" /run/lock/systemd-swap.zram
                  break
              else
                  continue
              fi
          done
      ;;
      stop)
          . /run/lock/systemd-swap.zram
          swapoff /dev/$dev
          write 1 /sys/block/$dev/reset
          rm /run/lock/systemd-swap.zram
      ;;
  esac
}

manage_swapf(){
  case $1 in
      start)
          [[ -z ${swapf_path[0]} || -z $swapf_size ]] && return 0
          loopdevs=()
          for n in ${swapf_path[@]}; do
              if [ ! -f "$n" ]; then
                  truncate -s $swapf_size $n || return 0
                  chmod 0600 $n
                  mkswap $n
              fi
              lp=`losetup -f`
              loopdevs=(${loopdevs[@]} $lp)
              losetup $lp $n
          done
          swapon ${loopdevs[@]}
          write "loopdevs=( ${loopdevs[@]} )" /run/lock/systemd-swap.swapf
      ;;
      stop)
          . /run/lock/systemd-swap.swapf
          [ -z ${loopdevs[@]} ] || swapoff ${loopdevs[@]}
          [ -z ${loopdevs[@]} ] || losetup -d ${loopdevs[@]}
          rm /run/lock/systemd-swap.swapf
      ;;
  esac
}

manage_swapdev(){
  case $1 in
      start)
          [ -z ${swap_dev[0]} ] && return 0
          swapon -p 1 ${swap_dev[@]} || :
          write "swap_dev=( ${swap_dev[@]} )" /run/lock/systemd-swap.dev
      ;;
      stop)
          . /run/lock/systemd-swap.dev
          if [ ! -z ${swap_dev[0]} ]; then
              swapoff ${swap_dev[@]} || :
          fi
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

  [ -z "$parse_fstab"  ] || tmp="`grep '^[^#]*swap' /etc/fstab || :`"
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

  [ -z  $parse_zswap ] || zswap=(`dmesg | grep "loading zswap" || :`)
  [ -z "$zswap" ] || unset zram_size zram_num_devices zswap
}

handle_cache(){
  [ -z $zram_streams    ] || A=( ${A[@]} zram_streams=$zram_streams        )
  [ -z $zram_size       ] || A=( ${A[@]} zram_size=$zram_size              )
  [ -z $swapf_size      ] || A=( ${A[@]} swapf_size=$swapf_size            )
  [ -z $zram_compress   ] || A=( ${A[@]} zram_compress=$zram_compress      )
  [ -z ${swapf_path[0]} ] || A=( ${A[@]} "swapf_path=( ${swapf_path[@]} )" )
  [ -z ${swap_dev[0]}   ] || A=( ${A[@]} "swap_dev=( ${swap_dev[@]} )"     )
  if [ -z ${A[0]} ]; then
      touch $cached_config &
  else
      write "export ${A[@]}" $cached_config &
  fi
}

manage_config(){
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
}

################################################################################
d=/run/lock/systemd-swap
case $1 in
    start)
        manage_config
        [ -f $d.zram  ] || manage_zram    $1 &
        [ -f $d.dev   ] || manage_swapdev $1 &
        [ -f $d.swapf ] || manage_swapf   $1 &
    ;;
    stop)
        [ -f $d.zram  ] && manage_zram    $1 &
        [ -f $d.dev   ] && manage_swapdev $1 &
        [ -f $d.swapf ] && manage_swapf   $1 &
    ;;
    reset)
        $0 stop || :
        manage_config
        for n in ${swapf_path[@]} $cached_config; do
            [ -f $n ] && rm -v $n
        done
        $0 start || :
    ;;
esac
wait
