#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n"
    echo -e "example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

SIFTR2_NAME="siftr2.ko"  # Module name
SIFTR2_PATH="/root/siftr2"	# Module location

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

log_review_tool="/root/review_siftr2_log/review_siftr2_log"
if [[ -f "${log_review_tool}" && -x "${log_review_tool}" ]]; then
    echo "${log_review_tool} exists and is executable."
else
    echo "${log_review_tool} does not exist or is not executable."
    exit 1
fi

dir=$(pwd)
tcp_port=54321
log_name=${dir}/${src}.test.log
siftr_name=${src}.${name}.siftr2
netstat_file_name=${dir}/${src}.${name}.netstat
iperf_log_name=${dir}/${src}.iperf3_output.log
throughput_timeline=${dir}/${src}.mbps_timeline.txt
snd_avg_goodput=${dir}/${src}.avg.goodput
tmp_name=${dir}/${src}.tmp.log

sysctl net.inet.tcp.functions_default | tee ${log_name}
# Don't cache ssthresh from previous connection
sysctl net.inet.tcp.hostcache.enable=0 | tee -a ${log_name}
# force to close the control socket after 4 seconds
sysctl net.inet.tcp.msl=2000 | tee -a ${log_name}
sysctl net.inet.tcp.cc.algorithm=${name} | tee -a ${log_name}
sysctl net.inet.siftr2.port_filter=${tcp_port} | tee -a ${log_name}
sysctl net.inet.siftr2.cwnd_filter=1 | tee -a ${log_name}
sysctl net.inet.siftr2.ppl=1 | tee -a ${log_name}
sysctl net.inet.siftr2.logfile=/var/log/${siftr_name} | tee -a ${log_name}
netstat -sz > /dev/null 2>&1
sysctl net.inet.siftr2.enabled=1 | tee -a ${log_name}

iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
sysctl net.inet.siftr2.enabled=0 | tee -a ${log_name}
netstat -sp tcp > ${netstat_file_name}

sleep 1

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}' ${iperf_log_name} > ${tmp_name}
sed '1d' ${tmp_name} | sed '$d' | sed '$d' > ${throughput_timeline}

# Run the binary and extract the flow_id value
siftr2_log_abs_path=$(realpath /var/log/${siftr_name})
flow_id=$(${log_review_tool} -f "${siftr2_log_abs_path}" | awk -F'id:' '{print $2}' | awk '{print $1}' | tr -d '\r\n')
${log_review_tool} -f "${siftr2_log_abs_path}" -p "${src}" -s "${flow_id}" >> "${log_name}" 2>&1

plot_file=${src}.${flow_id}.txt
echo "flow_id: [$flow_id]"
echo "plot_file: [$plot_file]"

ls -lh "${siftr2_log_abs_path}" | tee -a ${log_name}
ls -lh "${plot_file}" | tee -a ${log_name}
tar -zcf ${siftr_name}.tgz -C /var/log ${siftr_name}
rm ${siftr2_log_abs_path}; rm ${tmp_name}
