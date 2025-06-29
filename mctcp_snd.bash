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

dir=$(pwd)
iperf_server_port=5001
iperf3_server_port=5201
log_name="${src}.test.log"
trace_name="${src}.${name}.trace"
tcpdump_name="${src}.${name}.pcap"
iperf_log_name="${src}.iperf_output.log"
snd_avg_goodput="${src}.avg.goodput"
throughput_timeline="${src}.mbps_timeline.txt"

uname -rv | tee ${log_name}
sysctl net.mptcp | tee -a ${log_name}
sysctl net.ipv4.tcp_congestion_control=${name} | tee -a ${log_name}
num_subflows=$(cat /sys/module/mptcp_ndiffports/parameters/num_subflows | tr -d '\r\n')
echo "/sys/module/mptcp_ndiffports/parameters/num_subflows = ${num_subflows}" | tee -a ${log_name}

trace_parser="/root/tcp_probe_parser/tcp_probe_parser"
if [[ -f "${trace_parser}" && -x "${trace_parser}" ]]; then
    echo "${trace_parser} exists and is executable."
else
    echo "${trace_parser} does not exist or is not executable."
    exit 1
fi

echo "dport == ${iperf_server_port}" > /sys/kernel/debug/tracing/events/tcp/tcp_probe/filter
echo 512000 > /sys/kernel/debug/tracing/buffer_size_kb
echo > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable

#iperf3 -B ${src} -c ${dst} -p ${iperf3_server_port} -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
iperf -B ${src} -c ${dst} -l 1M -t ${seconds} -i 1 -f m -eZ ${name} > ${iperf_log_name}

echo 0 > /sys/kernel/debug/tracing/events/tcp/tcp_probe/enable
## remove error message that does not match format
rg "tcp_probe" /sys/kernel/debug/tracing/trace | rg -v "rs:main" > ${trace_name}
echo > /sys/kernel/debug/tracing/trace

du -h ${trace_name}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}'\
    ${iperf_log_name} | sed '$d' > ${throughput_timeline}
tail -n 1 ${iperf_log_name} | awk '{printf "%.1f\n", $7}' > ${snd_avg_goodput}
avg_goodput=$(cat "${snd_avg_goodput}" | tr -d '\r\n')
echo "sender average throughput: [${avg_goodput}]"

# Run the binary and extract the flow_id value
${trace_parser} -f "${trace_name}" -p "${src}" -a | tee -a ${log_name}


# Iterate over each file and apply the function
for tracefile in "${per_socket_trace_dir}"/subflow_*.log; do
    [ -e "${tracefile}" ] || continue  # skip if no match
    generate_plot_file_per_trace_file $(realpath ${tracefile})
done

subflow_files=(${per_socket_trace_dir}/subflow_*.log)
num_subflow_files=${#subflow_files[@]}
#for trace_file in "${subflow_files[@]}"; do
#    [ -e "${trace_file}" ] || continue  # skip if no match
#    num_lines=$(wc -l "${trace_file}" | awk '{printf "%d\n", $1}')
#    if [ "${num_lines}" -lt 10 ]; then
#        rm "${trace_file}"
#    fi 
#done
# for a single flow created by iperf, there should be only two subflows


global_max_cwnd=0
global_max_srtt=0
plot_data_files=("${src}.plot_files"/*.txt)
num_plot_data_files=${#plot_data_files[@]}
[ "${num_subflows}" = "${num_plot_data_files}" ] || \
{ echo "Assertion failed: ${num_subflows} != ${num_plot_data_files}"; exit 1; }

for plot_file in "${plot_data_files[@]}"; do
    [ -e "${plot_file}" ] || continue  # skip if no match
    read min_cwnd avg_cwnd max_cwnd min_srtt avg_srtt max_srtt <<< $(awk '
    NR > 1 {
        cwnd_sum += $2
        srtt_sum += $3
        if (min_cwnd == "" || $2 < min_cwnd) min_cwnd = $2
        if (max_cwnd == "" || $2 > max_cwnd) max_cwnd = $2
        if (min_srtt == "" || $3 < min_srtt) min_srtt = $3
        if (max_srtt == "" || $3 > max_srtt) max_srtt = $3
        count++
    }
    END {
        print min_cwnd, cwnd_sum/count, max_cwnd, min_srtt, srtt_sum/count, max_srtt
    }' "${plot_file}")
    if [ "${global_max_cwnd}" -lt "$[max_cwnd]" ]; then
        global_max_cwnd=${max_cwnd}
    fi
    if [ "${global_max_srtt}" -lt "$[max_srtt]" ]; then
        global_max_srtt=${max_srtt}
    fi
done
ymax_cwnd=$(echo "${global_max_cwnd} * 1.25" | bc)
ymax_srtt=$(echo "${global_max_srtt} * 1.25" | bc)

echo "generating gnuplot figure..."
# Start building the gnuplot command
{
    cwnd_title_str="${src} ${name} cwnd chart"
    srtt_title_str="${src} ${name} srtt chart"
    num_plot_data_files=${#plot_data_files[@]}
    pt_interval=$((seconds * 100))

    echo "set encoding utf8"
    echo "set term pdfcairo color lw 1 dashlength 1 enhanced font\
          'DejaVu Sans Mono,16' dashed size 12in,9in background rgb 'white'"
    echo "set output '${src}.cwnd_srtt.pdf'"
    echo "set multiplot layout 2,1 title 'Flow Analysis' offset 4.0,0.0"
    echo "set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval \
          ${pt_interval}"
    echo "set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval \
          ${pt_interval}"
    echo "set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval \
          ${pt_interval}"
    echo "set xtics nomirror"
    echo "set ytics nomirror"
    echo "set tmargin 3"
    echo "set mxtics"
    echo "set autoscale fix"
    echo "set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5"
    echo "set boxwidth 2 relative"
    echo "set xlabel 'time (second)'"
    echo "set xrange [0:${seconds}]"

    # First plot cwnd
    echo "set title '${cwnd_title_str}'"
    echo "set ylabel 'cwnd (segments)'"
    echo "set yrange [0:${ymax_cwnd}]"
    echo -n "plot "

    for ((i = 0; i < num_plot_data_files; i++)); do
        file="${plot_data_files[$i]}"
        fname="subflow$((i + 1))"
        echo -n "'${file}' using 1:2 title '${fname}' with linespoints ls $((i + 1))"
    
        # Add comma only if not the last file
        if (( i < num_plot_data_files -1 )); then
          echo -n ", "
        fi
    done
    echo ""
    
    # Second plot
    echo "set title '${srtt_title_str}'"
    echo "set ylabel 'srtt (microsecond)'"
    echo "set yrange [0:${ymax_srtt}]"
    echo -n "plot "

    for ((i = 0; i < num_plot_data_files; i++)); do
        file="${plot_data_files[$i]}"
        fname="subflow$((i + 1))"
        echo -n "'${file}' using 1:3 title '${fname}' with linespoints ls $((i + 1))"
    
        # Add comma only if not the last file
        if (( i < num_plot_data_files -1 )); then
          echo -n ", "
        fi
    done
    echo ""
    echo "unset multiplot"
    echo "unset output"
} | gnuplot

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)

printf "Execution time: %.1f seconds\n" "$elapsed"
