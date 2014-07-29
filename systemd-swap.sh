#!/bin/bash -e

write(){
    [ "$#" == "2" ] || return 0
    val="$1" file="$2"
    echo $val >>  $file
    echo "$val >> $file"
}

manage_zram(){
  case $1 in
      start)
          [ -z ${zram[size]} ] && return 0
          [ -f /dev/zram0   ] || modprobe zram num_devices=32
          zram[dev]=`zramctl find ${zram[size]} ${zram[alg]} ${zram[streams]}`
          mkswap /dev/${zram[dev]}
          swapon -p 32767 /dev/${zram[dev]}
          write "zram[dev]=${zram[dev]}" ${lock[zram]}
      ;;
      stop)
          . ${lock[zram]}
          swapoff /dev/${zram[dev]}
          strace zramctl reset ${zram[dev]}
          rm ${lock[zram]}
      ;;
  esac
}

manage_swapf(){
  case $1 in
      start)
          [ ! -z ${swapf[path]} ] || return 0
          [ ! -z ${swapf[size]} ] || return 0
          truncate -s ${swapf[size]} ${swapf[path]} || return 0
          chmod 0600 ${swapf[path]}
          mkswap ${swapf[path]}
          swapf[loop]=`losetup -f`
          losetup ${swapf[loop]} ${swapf[path]}
          swapon  ${swapf[loop]}
          losetup -d ${swapf[loop]} # set autoclear flag
          write "swapf[path]=${swapf[path]}" ${lock[swapf]}
          write "swapf[loop]=${swapf[loop]}" ${lock[swapf]}
      ;;
      stop)
          . ${lock[swapf]}
          if [ ! -z ${swapf[loop]} ]; then
              swapoff ${swapf[loop]}
          fi
          rm ${lock[swapf]} ${swapf[path]}
      ;;
  esac
}

manage_swapdev(){
  case $1 in
      start)
          [ -z "${swapd[devs]}" ] && return 0
          for i in `echo ${swapd[devs]}`; do
              if swapon -p 1 $i; then
                  write $i ${lock[dev]}
              else
                  :
              fi
          done
      ;;
      stop)
          for i in `cat ${lock[dev]}`; do
              swapoff $i || :
          done
          rm ${lock[dev]}
      ;;
  esac
}

###############################################################################
# Script body
declare -A sys zram lock swapf swapd

parse_config(){
  sys[cpu_count]=`grep -c ^processor /proc/cpuinfo`
  sys[ram_size]=`awk '/MemTotal:/ { print $2 }' /proc/meminfo`

  . $config

  [ -z ${swapf[fstab]} ] || \
  if [ ! -z "`grep '^[^#]*swap' /etc/fstab || :`" ]; then
     unset swapf
     echo Swap already specified in fstab
  fi

  if [ ! -z ${swapd[parse]} ]; then
     swapd[devs]=" `blkid -t TYPE=swap -o device | grep -vE '(zram|loop)' || :`
                   ${swapd[devs]}"
     [ ! -z ${swapf[Poff]} ] && [ ! -z "${swapd[devs]}" ] && unset swapf || :
  fi
}

manage_config(){
  config=/etc/systemd-swap.conf
  if [ -f $config ]; then
      parse_config
  else
      echo "Config $config deleted, reinstall package"
      exit 1
  fi
}

###############################################################################
lock[zram]=/run/lock/systemd-swap.zram
lock[dev]=/run/lock/systemd-swap.dev
lock[swapf]=/run/lock/systemd-swap.swapf
case $1 in
    start)
        manage_config
        [ -f ${lock[zram]}  ] || manage_zram    $1 &
        [ -f ${lock[dev]}   ] || manage_swapdev $1 &
        [ -f ${lock[swapf]} ] || manage_swapf   $1 &
    ;;
    stop)
        [ -f ${lock[zram]}  ] && manage_zram    $1 &
        [ -f ${lock[dev]}   ] && manage_swapdev $1 &
        [ -f ${lock[swapf]} ] && manage_swapf   $1 &
    ;;
esac
wait
