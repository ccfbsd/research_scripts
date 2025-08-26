#!/bin/bash

if [  $# -ne 2 ]; then
    echo -e "\nUsage:\n$0 <log_name> <mtu_size> \n example: bash $0 test.log 9000\n"
    exit 1
fi

loop_run() {
    local iperf_log_name="$1"
    local dev_mtu="$2"
    
    uname -v | tee ${iperf_log_name}
    sysctl net.inet.tcp.sendspace | tee -a ${iperf_log_name}
    sysctl net.inet.tcp.recvspace | tee -a ${iperf_log_name}
    sysctl net.inet.tcp.functions_default | tee -a ${iperf_log_name}
    # force to close the control socket after 4 seconds
    sysctl net.inet.tcp.msl=2000 | tee -a ${iperf_log_name}
    sysctl net.inet.siftr2.port_filter=5201 | tee -a ${iperf_log_name}

    ifconfig lo0 mtu ${dev_mtu}
    ifconfig lo0 | tee -a ${iperf_log_name}

    for i in {1..5}; do
        local siftr2_log_path="$(pwd)/siftr2.$i.log"
        sysctl net.inet.siftr2.logfile=${siftr2_log_path} | tee -a ${iperf_log_name}
        sysctl net.inet.siftr2.enabled=1 | tee -a ${iperf_log_name}
        iperf3 -B localhost -c localhost -t10 -i1 -Vfg >> ${iperf_log_name}
        sleep 8
        sysctl net.inet.siftr2.enabled=0 | tee -a ${iperf_log_name}
        sleep 2
    done
}

log_name=$1
dev_mtu=$2

start_time=$(date +%s.%N)

SIFTR2_NAME="siftr2.ko"  # Module name
SIFTR2_PATH="~/siftr2"  # Module location

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

loop_run ${log_name} ${dev_mtu}

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)

printf "Execution time: %.1f seconds\n" "$elapsed"