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
plot_dir="${src}.plot_files"

trace_parser="/root/tcp_probe_parser/tcp_probe_parser"
if [[ -f "${trace_parser}" && -x "${trace_parser}" ]]; then
    echo "${trace_parser} exists and is executable."
else
    echo "${trace_parser} does not exist or is not executable."
    exit 1
fi

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

## get the average throughput per timeline
if [ ${parallel} -gt 1 ]; then
    rg "SUM" ${iperf_log_name} | \
    awk '/sec/ {split($2, interval, "-"); printf "%d\t%s\n", int(interval[2]), $6}' |\
    sed '$d' > ${throughput_timeline}
else
    awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}'\
    ${iperf_log_name} | sed '$d' > ${throughput_timeline}
fi

## get the final average throughput
if [ ${parallel} -gt 1 ]; then
    tail -n 2 ${iperf_log_name} | rg "SUM" | awk '{printf "%.1f\n", $6}' > ${snd_avg_goodput}
else
    tail -n 1 ${iperf_log_name} | awk '{printf "%.1f\n", $7}' > ${snd_avg_goodput}
fi

avg_goodput=$(cat ${snd_avg_goodput} | tr -d '\r\n')
echo "sender average throughput: [${avg_goodput}]"

# Run the binary and extract the flow_id value
${trace_parser} -f "${trace_name}" -p "${src}" -a | tee -a ${log_name}

declare -A avg_srtt min_srtt max_srtt avg_cwnd min_cwnd max_cwnd
# Parse test log
max_cwnd_global=0
max_srtt_global=0
while IFS= read -r line; do
    if [[ $line == *"flowid:"* ]]; then
        id=$(echo "$line" | grep -oP 'flowid:\s*\K[0-9]+')
        avg_tt=$(echo "$line" | grep -oP 'avg_srtt:\s*\K[0-9]+')
        min_tt=$(echo "$line" | grep -oP 'min_srtt:\s*\K[0-9]+')
        max_tt=$(echo "$line" | grep -oP 'max_srtt:\s*\K[0-9]+')
        avg_cw=$(echo "$line" | grep -oP 'avg_cwnd:\s*\K[0-9]+')
        min_cw=$(echo "$line" | grep -oP 'min_cwnd:\s*\K[0-9]+')
        max_cw=$(echo "$line" | grep -oP 'max_cwnd:\s*\K[0-9]+')
        avg_srtt[$id]=$avg_tt
        min_srtt[$id]=$min_tt
        max_srtt[$id]=$max_tt
        avg_cwnd[$id]=$avg_cw
        min_cwnd[$id]=$min_cw
        max_cwnd[$id]=$max_cw
        # Track global max cwnd and srtt
        if (( max_cw > max_cwnd_global )); then
            max_cwnd_global=$max_cw
        fi
        if (( max_tt > max_srtt_global )); then
            max_srtt_global=$max_tt
        fi
#        echo "${id} ${avg_srtt[$id]} ${min_srtt[$id]} ${max_srtt[$id]}" \
#             "${avg_cwnd[$id]} ${min_cwnd[$id]} ${max_cwnd[$id]}"
    fi
done < ${log_name}
total_socks=$(grep -oP 'flow_count:\s*\K[0-9]+' ${log_name})
ymax_cwnd=$(echo "${max_cwnd_global} + ${max_cwnd_global} * 0.2 * ${parallel}" | bc)
ymax_srtt=$(echo "${max_srtt_global} + ${max_srtt_global} * 0.2 * ${parallel}" | bc)
#echo "total_socks: [${total_socks}], ymax_cwnd: [${ymax_cwnd}], ymax_srtt: [${ymax_srtt}]"

echo "generating gnuplot figure..."

cwnd_title_str="sender '${src}' ${name} cwnd chart"
srtt_title_str="sender '${src}' ${name} srtt chart"
pt_interval=$((seconds * 100))

gnuplot -persist << EOF
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16"\
    dashed size 12in,9in background rgb "white"
set output "${src}.cwnd_srtt.pdf"
set multiplot layout 2,1 title "TCP Analysis" offset 4.0,0.0

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval ${pt_interval}
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval ${pt_interval}
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval ${pt_interval}
set style line 4 lc rgb 'orange' lt 1 lw 2 pt 4 pointsize 1 pointinterval ${pt_interval}

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
set ylabel "cwnd (segments)"
set yrange [0:${ymax_cwnd}]
plot \\
$( 
    count=0
    total=${total_socks}
    for id in "${!avg_cwnd[@]}"; do
        count=$((count+1))
        echo -n "'${plot_dir}/${id}.txt' using 1:2 title "\
                "'socket ${id} (avgCW=${avg_cwnd[$id]}, minCW=${min_cwnd[$id]},"\
                "maxCW=${max_cwnd[$id]} segments)' with linespoints ls $count"
        if [ $count -lt $total ]; then
            echo ", \\"
        else
            echo ""
        fi
    done
)

# Second plot
set title "${srtt_title_str}"
set ylabel "srtt (microsecond)"
set yrange [0:${ymax_srtt}]
plot \\
$( 
    count=0
    total=${total_socks}
    for id in "${!avg_srtt[@]}"; do
        count=$((count+1))
        echo -n "'${plot_dir}/${id}.txt' using 1:3 title "\
                "'socket ${id} (avgSRTT=${avg_srtt[$id]}, minSRTT=${min_srtt[$id]}," \
                "maxSRTT=${max_srtt[$id]} µs)' with linespoints ls $count"
        if [ $count -lt $total ]; then
            echo ", \\"
        else
            echo ""
        fi
    done
)

unset multiplot
unset output
EOF

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)

printf "Execution time: %.1f seconds\n" "$elapsed"
