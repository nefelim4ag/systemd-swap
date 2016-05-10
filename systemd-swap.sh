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

manage_zswap(){
    ZSWAP_P=/sys/module/zswap/parameters/
    case $1 in
        start)
            [ -f "${lock[zswap]}" ] && return 0
            declare -A local
            for param in enabled compressor max_pool_percent zpool; do
                local["$param"]="$(cat $ZSWAP_P/$param)"
                write "zswap[$param]=${local[$param]}" "${lock[zswap]}"
                write "${zswap[$param]}" "$ZSWAP_P/$param"
            done
        ;;
        stop)
            [ -f "${lock[zswap]}" ] || return 0
            . "${lock[zswap]}"
            for param in enabled compressor max_pool_percent zpool; do
                write "${zswap[$param]}" "$ZSWAP_P/$param"
            done
            rm ${lock[zswap]}
        ;;
    esac
}

read_line(){
    FILE=$1 NUM=$2
    head -n $NUM $FILE | tail -n 1
}

gen_vram_bounds(){
    FILE_TMP="$(mktemp)"
    lspci | grep VGA > $FILE_TMP
    VGA_COUNT="$(cat -n $FILE_TMP | wc -l)"
    for a in $(seq 1 $VGA_COUNT); do
        PCI_SLOT=$(read_line $FILE_TMP $a| awk '{print $1}')
        FILE_REGIONS_TMP="$(mktemp)"
        lspci -v -s $PCI_SLOT | grep '(64-bit, prefetchable)' > $FILE_REGIONS_TMP
        REGION_COUNT="$(cat -n $FILE_REGIONS_TMP | tail -n 1 | awk '{print $1}')"
        for b in $(seq 1 $REGION_COUNT); do
            LINE=$(read_line $FILE_REGIONS_TMP $b)
            REGION_START=$( echo $LINE | awk '{print $3}' )
            REGION_START_BYTE="$((16#$REGION_START))"
            REGION_LENGHT=$( echo $LINE | awk '{print $6}' | cut -d'=' -f2 | tr -d ']' )
            if echo $REGION_LENGHT | grep -q M; then
                REGION_LENGHT_MB="$(echo $REGION_LENGHT | tr -d 'M')"
                REGION_LENGHT_BYTE=$[$REGION_LENGHT_MB*1024*1024]
                REGION_END=$[$REGION_START_BYTE+$REGION_LENGHT_BYTE]
                vramswap_regions[${a}_${b}]="$REGION_START_BYTE $REGION_END"
            else
                echo "Can't compute VRAM Region size for $PCI_SLOT"
            fi
        done
    done
    rm $FILE_TMP
}

manage_vramswap(){
    case $1 in
        start)
            gen_vram_bounds
            U_REG_START="${vramswap[region_start]}"
            U_REG_START="$((16#$U_REG_START))"
            U_REG_END="${vramswap[region_size]}"
            U_REG_END="$((16#$U_REG_END))"
            U_REG_END="$[$U_REG_START+$U_REG_END]"
            MEM_REGION_OKAY=false
            for region in "${vramswap_regions[@]}"; do
                break
                START=$(echo $region | cut -d' ' -f1)
                END=$(echo $region | cut -d' ' -f2)
                if (( $U_REG_START >= $START )) && (( $U_REG_START < $END )); then
                    if (( $U_REG_END <= $END )); then
                        MEM_REGION_OKAY=true
                    else
                        continue
                    fi
                else
                    continue
                fi
            done
            if $MEM_REGION_OKAY; then
                modprobe slram map=VRAM,0x${vramswap[region_start]},+0x${vramswap[region_size]}
                modprobe mtdblock
                if [ -b /dev/mtdblock0 ]; then
                    mkswap -L VRAM /dev/mtdblock0
                    swapon -p 32767 /dev/mtdblock0
                fi
                write /dev/mtdblock0 ${lock[vramswap]}
            else
                echo "No one parsed region is acceptable for VRAM"
            fi
        ;;
        stop)
            swapoff /dev/mtdblock0
            rmmod slram mtdblock
        ;;
    esac
}

###############################################################################
# Script body
# Create associative arrays
declare -A sys zram lock swapf swapd zswap vramswap vramswap_regions

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
lock[zswap]=/run/.systemd-swap.zswap
lock[vramswap]=/run/.systemd-swap.vramswap
case $1 in
    start)
        manage_config
        # start several independent threads
        [ -f ${lock[zram]}  ] || manage_zram    $1 &
        [ -f ${lock[dev]}   ] || manage_swapdev $1 &
        [ -f ${lock[swapf]} ] || manage_swapf   $1 &
        [ -f ${lock[zswap]} ] || manage_zswap   $1 &
        [ -f ${lock[vramswap]} ] || manage_vramswap $1 &
    ;;
    stop)
        [ -f ${lock[zram]}  ] && manage_zram    $1 &
        [ -f ${lock[dev]}   ] && manage_swapdev $1 &
        [ -f ${lock[swapf]} ] && manage_swapf   $1 &
        [ -f ${lock[zswap]} ] && manage_zswap   $1 &
        [ -f ${lock[vramswap]} ] && manage_vramswap $1 &
    ;;
esac
wait
