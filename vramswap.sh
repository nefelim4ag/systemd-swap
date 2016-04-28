#!/bin/bash -e
FILE_TMP="$(mktemp)"
lspci | grep VGA > $FILE_TMP
read_line(){
    FILE=$1 NUM=$2
    head -n $NUM $FILE | tail -n 1
}

VGA_COUNT="$(cat -n $FILE_TMP | tail -n 1 | awk '{print $1}')"

for a in $(seq 1 $VGA_COUNT); do
    LINE=$(read_line $FILE_TMP $a)
    PCI_SLOT=$(echo $LINE | awk '{print $1}')
    FILE_REGIONS_TMP="$(mktemp)"
    lspci -v -s $PCI_SLOT | grep '(64-bit, prefetchable)' > $FILE_REGIONS_TMP
    REGION_COUNT="$(cat -n $FILE_REGIONS_TMP | tail -n 1 | awk '{print $1}')"
    echo $LINE
    for b in $(seq 1 $REGION_COUNT); do
        LINE_2=$(read_line $FILE_REGIONS_TMP $b)
        REGION_START=$( echo $LINE_2 | awk '{print $3}' )
        REGION_START_BYTE="$((16#$REGION_START))"
        echo Region $b start: $REGION_START \= ${REGION_START_BYTE}B \= $[${REGION_START_BYTE}/1024/1024]MB
        REGION_LENGHT=$( echo $LINE_2 | awk '{print $6}' | cut -d'=' -f2 | tr -d ']' )
        if echo $REGION_LENGHT | grep -q M; then
            REGION_LENGHT_MB="$(echo $REGION_LENGHT | tr -d 'M')"
            REGION_LENGHT_BYTE=$[$REGION_LENGHT_MB*1024*1024]
            REGION_LENGHT_HEX="$(printf "%x" $REGION_LENGHT_BYTE)"
            echo Region $b size: $REGION_LENGHT_HEX \= ${REGION_LENGHT_BYTE}B \= ${REGION_LENGHT_MB}MB
        else
            echo "Can't compute VRAM Region size"
        fi
    done
done
