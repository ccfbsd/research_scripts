#!/bin/bash

display_usage() {
        echo -e "\nUsage:\n$0 <name> <src> <dst>\n"
        echo -e "example: bash $0 cubic s1 r1\n"
}
if [  $# -ne 3 ]
then
	display_usage
	exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3

MODULE_NAME="siftr2.ko"  # Module name without .ko
MODULE_PATH="/root/siftr2"	# Module location

# Check if the module is already loaded
if ! kldstat | grep -q "$MODULE_NAME"; then
    echo "Module $MODULE_NAME is not loaded. Loading it now..."
    
    # Try loading the module
    if kldload ${MODULE_PATH}/${MODULE_NAME}; then
        echo "Module $MODULE_NAME loaded successfully."
    else
        echo "Failed to load module $MODULE_NAME. Check if the module exists or requires dependencies."
        exit 1
    fi
else
    echo "Module $MODULE_NAME is already loaded."
fi

dir=$(pwd)
tcp_port=54321
siftr_name=${src}.${name}.siftr2
tcpdump_name=${src}.${name}.pcap
netstat_file_name=${src}.${name}.netstat
iperf_log_name=${src}.iperf3_output.log
snd_avg_goodput=${src}.avg.goodput
tmp_name=${src}.tmp.log

sysctl net.inet.tcp.functions_default
sysctl net.inet.tcp.hostcache.enable=0    # Don't cache ssthresh from previous connection
sysctl net.inet.tcp.msl=2000              # force to close the control socket after 4 seconds
sysctl net.inet.tcp.cc.algorithm=${name}
sysctl net.inet.siftr2.port_filter=${tcp_port}
sysctl net.inet.siftr2.cwnd_filter=1
sysctl net.inet.siftr2.ppl=2
sysctl net.inet.siftr2.logfile=/var/log/${siftr_name}
netstat -sz > /dev/null 2>&1
sysctl net.inet.siftr2.enabled=1
# tcpdump -w ${tcpdump_name} -s 100 -i vtnet0 tcp port ${tcp_port} &
# pid=$!
# sleep 1

iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t 10 -i 1 -f m -VC ${name} > ${iperf_log_name}
sysctl net.inet.siftr2.enabled=0
netstat -sp tcp > ${dir}/${netstat_file_name}
# kill $pid

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}' ${iperf_log_name} > ${tmp_name}
sed '1d' ${tmp_name} | sed '$d' | sed '$d' > ${src}.time_mbps.txt

cd /var/log/
ls -lh ${siftr_name}
tar zcf ${siftr_name}.tgz ${siftr_name}
rm ${siftr_name}
mv /var/log/${siftr_name}.tgz ${dir}/
cd ${dir}/
rm ${tmp_name}
