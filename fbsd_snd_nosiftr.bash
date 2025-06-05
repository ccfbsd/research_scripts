#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

dir=$(pwd)
tcp_port=54321
log_name="${src}.test.log"
netstat_file_name="${src}.${name}.netstat"
iperf_log_name="${src}.iperf_output.log"
throughput_timeline="${src}.mbps_timeline.txt"
snd_avg_goodput="${src}.avg.goodput"

uname -v | tee ${log_name}
sysctl net.inet.tcp.functions_default | tee -a ${log_name}
# Don't cache ssthresh from previous connection
sysctl net.inet.tcp.hostcache.enable=0 | tee -a ${log_name}
# force to close the control socket after 4 seconds
sysctl net.inet.tcp.msl=2000 | tee -a ${log_name}
sysctl net.inet.tcp.cc.algorithm=${name} | tee -a ${log_name}
kldstat | tee -a ${log_name}
netstat -sz > /dev/null 2>&1

#iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
iperf -B ${src} -c ${dst} -t ${seconds} -i 1 -f m -Z ${name} > ${iperf_log_name}
netstat -sp tcp > ${netstat_file_name}

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}'\
    ${iperf_log_name} | sed '$d' > ${throughput_timeline}
tail -n 1 ${iperf_log_name} | awk '{printf "%.1f\n", $7}' > ${snd_avg_goodput}
