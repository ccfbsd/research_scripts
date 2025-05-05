#!/bin/bash

# Define a function to check if a folder is a leaf and generate a log
generate_thruput_plot_if_leaf() {
    local dir="$1"
    local bdp="$2"

    # Check if the directory has no subdirectories
    if ! find "${dir}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        local test_logs=(${dir}/*.test.log)
        # Check if exactly two matching test logs exist
        if [ ${#test_logs[@]} -ne 2 ] || [ ! -e "${test_logs[0]}" ] || [ ! -e "${test_logs[1]}" ]; then
            echo "Skipping ${dir}: required test logs not found"
            return
        fi
        # Extract prefixes
        local src1 src2
        src1=$(basename "${test_logs[0]}" | cut -d. -f1)
        src2=$(basename "${test_logs[1]}" | cut -d. -f1)
        echo "First prefix: $src1"
        echo "Second prefix: $src2"
        
        local flow1_summary=$(grep "<->" "${test_logs[0]}" | awk '{$1=$1; print}')
        local flow1_stack=$(echo "${flow1_summary}" | awk '{printf "%s\n", $3}' | cut -d: -f2)
        local flow1_cc=$(echo "${flow1_summary}" | awk '{printf "%s\n", $4}' | cut -d: -f2)

        local flow2_summary=$(grep "<->" "${test_logs[1]}" | awk '{$1=$1; print}')
        local flow2_stack=$(echo "${flow2_summary}" | awk '{printf "%s\n", $3}' | cut -d: -f2)
        local flow2_cc=$(echo "${flow2_summary}" | awk '{printf "%s\n", $4}' | cut -d: -f2)

        [ "${flow1_stack}" = "${flow2_stack}" ] || { echo "Assertion failed: ${flow1_stack} != ${flow2_stack}"; exit 1; }
        [ "${flow1_cc}" = "${flow2_cc}" ] || { echo "Assertion failed: ${flow1_cc} != ${flow2_cc}"; exit 1; }

        local iperf3_logs=(${dir}/*.iperf3_output.log)
        local ver_str="before patch:"
        # Check if exactly two matching test logs exist
        if [ ${#iperf3_logs[@]} -ne 2 ] || [ ! -e "${iperf3_logs[0]}" ] || [ ! -e "${iperf3_logs[1]}" ]; then
            echo "Skipping ${dir}: required iperf3 logs not found"
            return
        fi
        if grep -q "dirty" "${iperf3_logs[0]}" && grep -q "dirty" "${iperf3_logs[1]}"; then
            ver_str="after patch:"
        fi
        echo "${ver_str}"

        local output="${dir}/all_throughput_chart.pdf"
        local n1_mbps="${dir}/${src1}.mbps_timeline.txt"
        local n2_mbps="${dir}/${src2}.mbps_timeline.txt"
        local n1_avg="${dir}/${src1}.avg.goodput"
        local n2_avg="${dir}/${src2}.avg.goodput"
        local agg_mbps="${dir}/aggregated_time_mbps.txt"
        awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}' ${n1_mbps} ${n2_mbps} > ${agg_mbps}
        echo "generating gnuplot figure ${output}..."

gnuplot -persist <<EOF
set title "${ver_str} ${flow1_stack} stack ${flow1_cc} throughput ${bdp}"
set output "${output}"
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 8in,6in background rgb "white"
set xlabel "time (second)"
set ylabel "throughput (Mbits/sec)"
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:3e2]
set yrange [0:12e2]
set autoscale fix

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 4
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 4
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 4
set style line 4 lc rgb 'magenta' lt 1 lw 2 pt 4 pointsize 1 pointinterval 4
set style line 5 lc rgb '#7F7F7F' lt 3 lw 1 pointinterval 5                   # dashline gray
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

f1_avg_goodput = real(system("awk '{print}' ${n1_avg}"))
f2_avg_goodput = real(system("awk '{print}' ${n2_avg}"))
plot "${n1_mbps}" using 1:2 title sprintf("flow1: average throughput = %.1f Mbits/sec", f1_avg_goodput) with linespoints ls 1, \
     "${n2_mbps}" using 1:2 title sprintf("flow2: average throughput = %.1f Mbits/sec", f2_avg_goodput) with linespoints ls 2, \
     "${agg_mbps}" using 1:2 title sprintf("aggregated throughput: average link utilization = %.1f Mbits/sec", (f1_avg_goodput + f2_avg_goodput)) with linespoints ls 3
EOF
    fi
}

if [  $# -ne 1 ]; then
    echo -e "\nUsage:\n$0 <comment>\n example: bash $0 under 0.27%BDP bottleneck buffer\n"
    exit 1
fi

bdp_comment=$1

# Starting point (you can set this to any path)
root_dir="."

# Find all directories and apply the function
find "$root_dir" -type d | while read -r dir; do
    generate_thruput_plot_if_leaf "$dir" "${bdp_comment}"
done
