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
trace_name=${src}.${name}.trace
tcpdump_name=${src}.${name}.pcap
iperf_log_name=${src}.iperf3_output.log
snd_avg_goodput=${src}.avg.goodput
tmp_name=${src}.tmp.log
plot_file=${src}.plot.txt

echo "sport == ${tcp_port}" > /sys/kernel/debug/tracing/events/tcp/tcp_probe/filter
## disable scheduler debugging and prevent interference in the tcp_probe log
#echo 0 > /proc/sys/kernel/sched_debug
echo 256000 > /sys/kernel/debug/tracing/buffer_size_kb
echo > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable

iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
echo 0 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable
cat /sys/kernel/debug/tracing/trace > ${dir}/${trace_name}

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
awk 'NR==1 {start=$1} {printf "%.6f\t%s\t%d\t%s\n", $1 - start, $2, $2 * 1448, $3}' ${trace_name}.tmp.txt > ${plot_file}

## awk '{$1 += 10; print}' input.txt > output.txt

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}' ${iperf_log_name} > ${tmp_name}
sed '1d' ${tmp_name} | sed '$d' | sed '$d' > ${src}.mbps_timeline.txt

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

tar zcf ${trace_name}.tgz ${trace_name}
rm ${dir}/${trace_name}.tmp.txt ${tmp_name} ${trace_name}

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
cwnd_stats="avg_cwnd: ${avg_cwnd}, min_cwnd: ${min_cwnd}, max_cwnd: ${max_cwnd} bytes"
srtt_stats="avg_srtt: ${avg_srtt}, min_srtt: ${min_srtt}, max_srtt: ${max_srtt} µs"
#echo "[${max_cwnd}][${ymax_cwnd}]"
#echo "[${max_srtt}][${ymax_srtt}]"
#echo "[${cwnd_stats}]"
#echo "[${srtt_stats}]"

echo "generating gnuplot figure..."

cwnd_title_str="${src} ${name} cwnd chart"
srtt_title_str="${src} ${name} srtt chart"

gnuplot -persist << EOF
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 noenhanced font "DejaVu Sans Mono,16" dashed size 12in,9in background rgb "white"
set output "${src}.cwnd_srtt.pdf"
set multiplot layout 2,1 title "Flow Analysis" offset 4.0,0.0

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 100

# First plot cwnd
set title "${cwnd_title_str}"
set xlabel "time (second)"
set ylabel "cwnd (byte)"
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:${seconds}]
set yrange [0:${ymax_cwnd}]
set autoscale fix
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

plot "${plot_file}" using 1:3 title "flow1: ${cwnd_stats}" with linespoints ls 1

# Second plot
set title "${srtt_title_str}"
set xlabel "time (second)"
set ylabel "srtt (microsecond)"
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:${seconds}]
set yrange [0:${ymax_srtt}]
set autoscale fix
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

plot "${plot_file}" using 1:4 title "flow1: ${srtt_stats}" with linespoints ls 1

unset multiplot
unset output
EOF
