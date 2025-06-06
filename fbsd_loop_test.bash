#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

loop_run_without_drifting() {
    local name="$1"
    local src="$2"
    local dst="$3"
    local seconds="$4"
    local script="$5"
    
    local interval=$(echo "${seconds} * 1.1" | bc | awk '{printf "%d\n", $1}')
    local start_time=$(date +%s)
    local next_time=$(( start_time + interval ))
    echo "start_time: [${start_time}], interval: [${interval}]"

    for i in {1..3}; do
        folder="${name}.siftr.$i"
        mkdir -p ${folder}
        cd ${folder} || exit 1
    
        echo "[$(date +%s)] Running ${script} in ${folder}..."
        bash ${script} ${name} ${src} ${dst} ${seconds}
        finish_time=$(date +%s)
        echo "script running finished at: [${finish_time}]"
        cd ..
        echo -e "next run is scheduled at: [${next_time}], delta: [$(( next_time - finish_time ))]\n"
    
        while true; do
            local now=$(date +%s)
            if [ "$now" -lt "$next_time" ]; then
                sleep 0.1
            else
                next_time=$(( next_time + interval ))
                break
            fi
        done
    done
}

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

script=/root/research_scripts/fbsd_snd.bash

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

dir=$(pwd)
def_stack_folder="${dir}/def_stack"
mkdir -p ${def_stack_folder}
rack_stack_folder="${dir}/rack_stack"
mkdir -p ${rack_stack_folder}

cd ${def_stack_folder} || exit 1
loop_run_without_drifting ${name} ${src} ${dst} ${seconds} ${script}

cd ${rack_stack_folder} || exit 1
kldload "tcp_rack.ko"
sysctl net.inet.tcp.functions_default=rack
loop_run_without_drifting ${name} ${src} ${dst} ${seconds} ${script}


kldunload siftr2
