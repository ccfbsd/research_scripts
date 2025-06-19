#!/bin/bash

if [  $# -ne 5 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds> <num_of_streams> \n"
    echo -e " example: bash $0 cubic s1 r1 10 2\n"
    exit 1
fi

name=$1             # TCP congestion control name
src=$2
dst=$3
seconds=$4
parallel=$5         # number of parallel client streams to run

start_time=$(date +%s.%N)

dir="$(pwd)"
iperf_svr_port=5001
iperf3_svr_port=5201
log_name="${src}.test.log"
trace_name="${src}.${name}.trace"
tcpdump_name="${src}.${name}.pcap"
iperf_log_name="${src}.iperf_output.log"
snd_avg_goodput="${src}.avg.goodput"
throughput_timeline="${src}.mbps_timeline.txt"
tmp_name="${src}.tmp"
plot_file="${src}.plot.txt"

uname -rv | tee ${log_name}
sysctl net.ipv4.tcp_congestion_control=${name} | tee -a ${log_name}

echo "dport == ${iperf_svr_port}" > /sys/kernel/debug/tracing/events/tcp/tcp_probe/filter
echo 512000 > /sys/kernel/debug/tracing/buffer_size_kb
echo > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable

#iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
iperf -B ${src} -c ${dst} -t ${seconds} -i 1 -f m -eZ ${name} -P ${parallel} > ${iperf_log_name}
echo 0 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable

## remove error message that does not match format
rg "tcp_probe" /sys/kernel/debug/tracing/trace | rg -v "rs:main" > ${trace_name}
echo > /sys/kernel/debug/tracing/trace

du -h ${trace_name}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}'\
    ${iperf_log_name} | sed '$d' > ${throughput_timeline}

if [ ${parallel} -gt 1 ]; then
    tail -n 2 ${iperf_log_name} | rg "SUM" | awk '{printf "%.1f\n", $6}' > ${snd_avg_goodput}
else
    tail -n 1 ${iperf_log_name} | awk '{printf "%.1f\n", $7}' > ${snd_avg_goodput}
fi

## gsub(":", "", $4): Removes the colon from the timestamp ($4).
## gsub("snd_cwnd=", "", $13): Removes "snd_cwnd=" from the field ($13).
## gsub("srtt=", "", $16): Removes "srtt=" from the field ($16).
## print $4 "\t" $13: Outputs the cleaned timestamp and snd_cwnd values.
awk '/tcp_probe/ {gsub(":", "", $4); gsub("snd_cwnd=", "", $13);\
    gsub("srtt=", "", $16); print $4 "\t" $13 "\t" $16}' ${trace_name} > ${tmp_name}

## NR==1 {start=$1}: Sets the first timestamp as the start time (only for the first line).
## $1 - start: Subtracts the start timestamp from each subsequent timestamp to get a relative time.
## then print the snd_cwnd value, the cwnd in bytes and the srtt in microseconds
awk 'NR==1 {start=$1} {printf "%.6f\t%s\t%d\t%s\n", $1 - start, $2, $2 * 1448, $3}'\
    ${tmp_name} > ${plot_file}

du -h ${plot_file}

tar zcf ${trace_name}.tgz ${trace_name}
tar zcf ${plot_file}.tgz ${plot_file}

read min_cwnd avg_cwnd max_cwnd min_srtt avg_srtt max_srtt <<< $(awk '
NR > 1 {
	cwnd_sum += $3
	srtt_sum += $4
	if (min_cwnd == "" || $3 < min_cwnd) min_cwnd = $3
	if (max_cwnd == "" || $3 > max_cwnd) max_cwnd = $3
	if (min_srtt == "" || $4 < min_srtt) min_srtt = $4
	if (max_srtt == "" || $4 > max_srtt) max_srtt = $4
	count++
}
END {
	print min_cwnd, cwnd_sum/count, max_cwnd, min_srtt, srtt_sum/count, max_srtt
}' "${plot_file}")

ymax_cwnd=$(echo "$max_cwnd * 1.25" | bc)
ymax_srtt=$(echo "$max_srtt * 1.25" | bc)
avg_cwnd=$(echo "${avg_cwnd}" | awk '{printf "%d\n", $1}')
avg_srtt=$(echo "${avg_srtt}" | awk '{printf "%d\n", $1}')
cwnd_stats="avg\\\_cwnd: ${avg_cwnd}, min\\\_cwnd: ${min_cwnd}, max\\\_cwnd: ${max_cwnd} bytes"
srtt_stats="avg\\\_srtt: ${avg_srtt}, min\\\_srtt: ${min_srtt}, max\\\_srtt: ${max_srtt} µs"

echo "generating gnuplot figure..."

cwnd_title_str="${src} ${name} cwnd chart"
srtt_title_str="${src} ${name} srtt chart"
pt_interval=$((seconds * 100))

gnuplot -persist << EOF
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 12in,9in background rgb "white"
set output "${src}.cwnd_srtt.pdf"
set multiplot layout 2,1 title "Flow Analysis" offset 4.0,0.0

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval ${pt_interval}

set xtics nomirror
set ytics nomirror
set tmargin 3       # Top margin
set mxtics
set autoscale fix
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative
set xlabel "time (second)"
set xrange [0:${seconds}]

# First plot cwnd
set title "${cwnd_title_str}"
set ylabel "cwnd (byte)"
set yrange [0:${ymax_cwnd}]
plot "${plot_file}" using 1:3 title "flow1: ${cwnd_stats}" with linespoints ls 1

# Second plot
set title "${srtt_title_str}"
set ylabel "srtt (microsecond)"
set yrange [0:${ymax_srtt}]
plot "${plot_file}" using 1:4 title "flow1: ${srtt_stats}" with linespoints ls 1

unset multiplot
unset output
EOF

rm ${tmp_name} ${trace_name} ${plot_file}

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)

printf "Execution time: %.1f seconds\n" "$elapsed"
