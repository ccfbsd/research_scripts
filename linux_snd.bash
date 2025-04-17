#!/bin/bash

display_usage() {
	echo -e "\nUsage:\n$0 <trace log name> <src> <dst>\n"
	echo -e "example: bash $0 cubic n1 n2\n"
}
if [  $# -ne 3 ]
then
	display_usage
	exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3

dir=$(pwd)
tcp_port=54321
trace_name=${src}.${name}.trace
tcpdump_name=${src}.${name}.pcap
iperf_log_name=${src}.iperf3_output.log
snd_avg_goodput=${src}.avg.goodput
tmp_name=${src}.tmp.log

echo "sport == ${tcp_port}" > /sys/kernel/debug/tracing/events/tcp/tcp_probe/filter
## disable scheduler debugging and prevent interference in the tcp_probe log
#echo 0 > /proc/sys/kernel/sched_debug
echo 256000 > /sys/kernel/debug/tracing/buffer_size_kb
echo > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable
# tcpdump -w ${tcpdump_name} -s 100 -i enp0s5 tcp port ${tcp_port} &
# pid=$!
sleep 1
iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t 300 -i 1 -f m -VC ${name} > ${iperf_log_name}
echo 0 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable
cat /sys/kernel/debug/tracing/trace > ${dir}/${trace_name}
# kill $pid

ls -lh ${trace_name}

## gsub(":", "", $4): Removes the colon from the timestamp ($4).
## gsub("snd_cwnd=", "", $13): Removes "snd_cwnd=" from the congestion window field ($13).
## gsub("srtt=", "", $16): Removes "srtt=" from the smoothed round-trip time ($16).
## print $4 "\t" $13: Outputs the cleaned timestamp and snd_cwnd values separated by a tab.
awk '/tcp_probe/ {gsub(":", "", $4); gsub("snd_cwnd=", "", $13); gsub("srtt=", "", $16); print $4 "\t" $13 "\t" $16}' ${trace_name} > ${trace_name}.tmp.txt

## NR==1 {start=$1}: Sets the first timestamp as the start time (only for the first line).
## $1 - start: Subtracts the start timestamp from each subsequent timestamp to get a relative time.
## "\t" $2: Prints the relative timestamp followed by the snd_cwnd value, separated by a tab.
## then print the cwnd in bytes and the srtt in microseconds
awk 'NR==1 {start=$1} {printf "%.6f\t%s\t%d\t%s\n", $1 - start, $2, $2 * 1448, $3}' ${trace_name}.tmp.txt > filtered_cwnd.${trace_name}.txt

## awk '{$1 += 10; print}' input.txt > output.txt

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}' ${iperf_log_name} > ${tmp_name}
sed '1d' ${tmp_name} | sed '$d' | sed '$d' > ${src}.time_mbps.txt

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

tar zcf ${trace_name}.tgz ${trace_name}
rm ${dir}/${trace_name}.tmp.txt ${tmp_name} ${trace_name}
