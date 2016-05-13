#!/bin/bash -e
################################################################################
# echo wrappers
INFO(){ echo -n "INFO: "; echo "$@" ;}
WARN(){ echo -n "WARN: "; echo "$@" ;}
ERRO(){ echo -n "ERRO: "; echo -n "$@" ; echo " Abort!"; exit 1;}

################################################################################
# helper function for see information about writing data
write(){
    [ "$#" == "2" ] || return 0
    val="$1" file="$2"
    [ ! -z "$val"  ] || return 0
    [ ! -z "$file" ] || return 0
    INFO "$val >> $file"
    echo "$val" >> "$file" || \
        WARN "Problem with writing $val >> $file"
}

zram_hot_add(){
    WARN "zramctl can't find free device"
    INFO "Use workaround hook for hot add"
    if [ -f /sys/class/zram-control/hot_add ]; then
        NEW_ZRAM=$(cat /sys/class/zram-control/hot_add)
        INFO "Success: new device /dev/zram$NEW_ZRAM"
    else
        ERRO "This kernel not support hot add zram device, please use 4.2+ kernels or see modinfo zram and make modprobe rule"
    fi
}

manage_zram(){
    case $1 in
        start)
            [ -z "${zram[size]}" ] && return 0
            zram[alg]=${zram[alg]:-lzo}
            zram[streams]=${zram[streams]:-${sys[cpu_count]}}
            zram[force]=${zram[force]:-true}
            # Wrapper, for handling zram initialization problems
            for (( i = 0; i < 10; i++ )); do
                [ -d /sys/module/zram ] || modprobe zram
            done
            for (( i = 0; i < 10; i++ )); do
                # zramctl is a external program -> return name of first free device
                OUTPUT="$(zramctl -f -a ${zram[alg]} -t ${zram[streams]} -s ${zram[size]} 2>&1 || :)"
                if echo "$OUTPUT" | grep -q "failed to reset: Device or resource busy"; then
                    sleep 1
                    continue
                elif echo "$OUTPUT" | grep -q "zramctl: no free zram device found"; then
                    zram_hot_add
                elif echo "$OUTPUT" | grep -q "/dev/zram"; then
                    zram[dev]="$OUTPUT"
                    break
                else
                    :
                fi
            done
            mkswap "${zram[dev]}"
            swapon -p 32767 "${zram[dev]}"
            write "zram[dev]=${zram[dev]}" ${lock[zram]}
        ;;
        stop)
            # read info from zram lock file
            . "${lock[zram]}"
            swapoff "${zram[dev]}"
            zramctl -r "${zram[dev]}"
            rm "${lock[zram]}"
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
                ERRO "Can't compute VRAM Region size for $PCI_SLOT!"
            fi
        done
    done
    rm $FILE_TMP
}

manage_vramswap(){
    case $1 in
        start)
            [ -f "${lock[vramswap]}" ] && return 0
            [ -z "${vramswap[region_start]}" ] && return 0
            [ -z "${vramswap[region_size]}"  ] && return 0
            if [ -b /dev/mtdblock0 ]; then
                ERRO "Can't handle VRAM SWAP if /dev/mtdblock0 exist before first systemd-swap initialization!"
            fi
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
                ERRO "No one parsed region is acceptable for VRAM!"
            fi
        ;;
        stop)
            swapoff "$(cat ${lock[vramswap]})"
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
     INFO "Swap already specified in fstab, so disable swap file creation"
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
      ERRO "Config $config deleted, reinstall package"
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
