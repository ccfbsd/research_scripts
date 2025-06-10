#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

start_time=$(date +%s.%N)

dir="$(pwd)"
iperf_svr_port=5001
iperf3_svr_port=5201
log_name="${src}.test.log"
iperf_log_name="${src}.iperf_output.log"
snd_avg_goodput="${src}.avg.goodput"
throughput_timeline="${src}.mbps_timeline.txt"

uname -rv | tee ${log_name}
sysctl net.ipv4.tcp_congestion_control=${name} | tee -a ${log_name}

#iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
iperf -B ${src} -c ${dst} -t ${seconds} -i 1 -f m -eZ ${name} > ${iperf_log_name}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}'\
    ${iperf_log_name} | sed '$d' > ${throughput_timeline}
tail -n 1 ${iperf_log_name} | awk '{printf "%.1f\n", $7}' > ${snd_avg_goodput}

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)

printf "Execution time: %.1f seconds\n" "$elapsed"