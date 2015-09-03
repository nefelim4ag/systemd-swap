#!/bin/bash -e

# helper function for see information about writing data
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
          # if module not loaded create many zram devices for users needs
          [ -f /dev/zram0 ] || modprobe zram num_devices=32
          zram[alg]=${zram[alg]:-lzo}
          zram[streams]=${zram[streams]:-${sys[cpu_count]}}
          zram[force]=${zram[force]:-true}
          # Wrapper, for handling zram initialization problems
          while :; do
              # zramctl is a external program -> return name of first free device
              if zram[dev]=$(zramctl -f -a ${zram[alg]} -t ${zram[streams]} -s ${zram[size]}); then
                  break
              else
                  # if force option disabled, just break loop
                  if ! ${zram[force]}; then
                      break
                  fi
                  sleep 1
              fi
          done
          mkswap ${zram[dev]}
          swapon -p 32767 ${zram[dev]}
          write "zram[dev]=${zram[dev]}" ${lock[zram]}
      ;;
      stop)
          # read info from zram lock file
          . ${lock[zram]}
          swapoff ${zram[dev]}
          zramctl -r ${zram[dev]}
          rm ${lock[zram]}
      ;;
  esac
}

manage_swapf(){
  case $1 in
      start)
          [ -z ${swapf[path]} ] && return 0
          [ -z ${swapf[size]} ] && return 0
          # Create sparse file for swap
          truncate -s ${swapf[size]} ${swapf[path]} || return 0
          # get first free loop device and
          # use swap file through loop, for avoid error:
          # skipping - it appears to have holes
          swapf[loop]=`losetup -f --show ${swapf[path]}`
          # loop use file descriptor, file still exist, but no have path
          # When loop deatach file, file will be deleted.
          rm ${swapf[path]}
          mkswap ${swapf[loop]}
          swapon -d ${swapf[loop]}
          # set autoclear flag
          losetup -d ${swapf[loop]}
          write "swapf[loop]=${swapf[loop]}" ${lock[swapf]}
      ;;
      stop)
          . ${lock[swapf]}
          if [ ! -z ${swapf[loop]} ]; then
              swapoff ${swapf[loop]}
          fi
          rm ${lock[swapf]}
      ;;
  esac
}

manage_swapdev(){
  case $1 in
      start)
          [ -z "${swapd[devs]}" ] && return 0
          for i in `echo ${swapd[devs]}`; do
              if swapon -d -p 1 $i; then
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
# Create associative arrays
declare -A sys zram lock swapf swapd

parse_config(){
  # get cpu count from cpuinfo
  sys[cpu_count]=$(nproc)
  # get total ram size for meminfo
  sys[ram_size]=$(awk '/MemTotal:/ { print $2 }' /proc/meminfo)

  # get values from /etc/systemd-swap.conf
  . $config

  # Parse fstab for swap mounts
  [ -z ${swapf[fstab]} ] || \
  if [ ! -z "`grep '^[^#]*swap' /etc/fstab || :`" ]; then
     unset swapf
     echo Swap already specified in fstab
  fi

  # Try to auto found swap partitions
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
lock[zram]=/run/.systemd-swap.zram
lock[dev]=/run/.systemd-swap.dev
lock[swapf]=/run/.systemd-swap.swapf
case $1 in
    start)
        manage_config
        # start several independent threads
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
