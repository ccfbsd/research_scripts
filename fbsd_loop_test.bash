#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

SIFTR2_NAME="siftr2.ko"  # Module name
SIFTR2_PATH="/root/siftr2"  # Module location

# Check if the module is already loaded
if ! kldstat | grep -q "$SIFTR2_NAME"; then
    echo "Module $SIFTR2_NAME is not loaded. Loading it now..."
    
    # Try loading the module
    if kldload ${SIFTR2_PATH}/${SIFTR2_NAME}; then
        echo "Module $SIFTR2_NAME loaded successfully."
    else
        echo "Failed to load module $SIFTR2_NAME. Check if the module exists or requires dependencies."
        exit 1
    fi
else
    echo "Module $SIFTR2_NAME is already loaded."
fi

interval=$(( seconds + 30 ))

start_time=$(date +%s)
next_time=$(( start_time + interval ))
echo "start_time: [$start_time], interval: [$interval]"

script=/root/research_scripts/fbsd_snd.bash
for i in {1..5}; do
    folder="${name}.siftr.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "[$(date +%s)] Running ${script} in $folder..."
    bash ${script} ${name} ${src} ${dst} ${seconds}
    echo "script running finished at: [$(date +%s)]"
    cd ..
    echo -e "next run is scheduled at: [${next_time}]\n"

    while true; do
        now=$(date +%s)
        if [ "$now" -lt "$next_time" ]; then
            sleep 0.1
        else
            next_time=$(( next_time + interval ))
            break
        fi
    done

done

kldunload siftr2
