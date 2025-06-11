#!/bin/bash

# Define a function to check if a folder is a leaf and generate a log
generate_thruput_plot_if_leaf() {
    local dir="$1"
    local sec="$2"
    local bdp="$3"

    # Check if the directory has no subdirectories
    if ! find "${dir}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        local iperf_logs=(${dir}/*.iperf_output.log)
        local ver_str="before patch:"
        # Check if exactly two matching iperf logs exist
        if [ ${#iperf_logs[@]} -ne 2 ] || [ ! -e "${iperf_logs[0]}" ] || [ ! -e "${iperf_logs[1]}" ]; then
            echo "Skipping ${dir}: required iperf logs not found"
            return
        fi

        local test_logs=(${dir}/*.test.log)
        # Check if exactly two matching test logs exist
        if [ ${#test_logs[@]} -ne 2 ] || [ ! -e "${test_logs[0]}" ] || [ ! -e "${test_logs[1]}" ]; then
            echo "Skipping ${dir}: required test logs not found"
            return
        fi
        if grep -q "dirty" "${test_logs[0]}" && grep -q "dirty" "${test_logs[1]}"; then
            ver_str="after patch:"
        fi
        # Extract prefixes
        local src1 src2
        src1=$(basename "${test_logs[0]}" | cut -d. -f1)
        src2=$(basename "${test_logs[1]}" | cut -d. -f1)
        
        local flow1_stack=$(grep "functions_default" "${test_logs[0]}" | awk '{printf "%s\n", $2}')
        local flow1_cc=$(grep "TCP congestion control set to" "${iperf_logs[0]}" | awk '{printf "%s\n", $6}')
        local flow2_stack=$(grep "functions_default" "${test_logs[1]}" | awk '{printf "%s\n", $2}')
        local flow2_cc=$(grep "TCP congestion control set to" "${iperf_logs[1]}" | awk '{printf "%s\n", $6}')
        [ "${flow1_stack}" = "${flow2_stack}" ] || { echo "Assertion failed: ${flow1_stack} != ${flow2_stack}"; exit 1; }
        [ "${flow1_cc}" = "${flow2_cc}" ] || { echo "Assertion failed: ${flow1_cc} != ${flow2_cc}"; exit 1; }
        local cc_algo=$(echo "$flow1_cc" | tr 'A-Z' 'a-z')      ## lower case

        local n1_mbps="${dir}/${src1}.mbps_timeline.txt"
        local n1_mbps_sec="${dir}/${src1}.mbps_timeline.${sec}.txt"
        local n2_mbps="${dir}/${src2}.mbps_timeline.txt"
        local n2_mbps_sec="${dir}/${src2}.mbps_timeline.${sec}.txt"
        awk -v sec="${sec}" '$1 <= sec' "${n1_mbps}" > "${n1_mbps_sec}"
        awk -v sec="${sec}" '$1 <= sec' "${n2_mbps}" > "${n2_mbps_sec}"
        
        read n1_avg_sec <<< $(awk ' NR > 1 { mbps_sum += $2; count++; } 
        END { print int(mbps_sum/count) }' "${n1_mbps_sec}")
        
        read n2_avg_sec <<< $(awk ' NR > 1 { mbps_sum += $2; count++; } 
        END { print int(mbps_sum/count) }' "${n2_mbps_sec}")
        
        local n1_avg="${dir}/${src1}.avg.${sec}.goodput"
        echo ${n1_avg_sec} > ${n1_avg}
        local n2_avg="${dir}/${src2}.avg.${sec}.goodput"
        echo ${n2_avg_sec} > ${n2_avg}
        
        local agg_mbps_sec="${dir}/aggregated_time_mbps.${sec}.txt"
        awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}'\
            ${n1_mbps_sec} ${n2_mbps_sec} > ${agg_mbps_sec}
        
        local output_file="all_throughput_chart_${sec}.pdf"
        local thruput_output="${dir}/${output_file}"
        echo "generating gnuplot figure ${output_file}"

        throughput_title_str="${ver_str} ${flow1_stack} stack ${cc_algo} throughput ${bdp}"

gnuplot -persist <<EOF
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 8in,6in background rgb "white"
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative
set xtics nomirror
set ytics nomirror
set tmargin 3       # Top margin
set mxtics
set autoscale fix
set xlabel "time (second)"
set xrange [0:${sec}]

# plot throughput
set title "${throughput_title_str}"
set output "${thruput_output}"
set ylabel "throughput (Mbits/sec)"
set yrange [0:12e2]
# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 4
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 4
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 4

f1_avg_sec = real(system("awk '{print}' ${n1_avg}"))
f2_avg_sec = real(system("awk '{print}' ${n2_avg}"))
link_avg_sec = (f1_avg_sec + f2_avg_sec)
plot "${n1_mbps_sec}" using 1:2 title sprintf("flow1: first %d seconds average throughput = %.1f Mbits/sec", ${sec}, f1_avg_sec) with linespoints ls 1, \
     "${n2_mbps_sec}" using 1:2 title sprintf("flow2: first %d seconds average throughput = %.1f Mbits/sec", ${sec}, f2_avg_sec) with linespoints ls 2, \
     "${agg_mbps_sec}" using 1:2 title sprintf("first %d seconds average link utilization = %.1f Mbits/sec", ${sec}, link_avg_sec) with linespoints ls 3
EOF
    fi
}

# Define a function to check if a folder is a leaf and generate a log
generate_cwnd_plot_if_leaf() {
    local dir="$1"
    local sec="$2"
    local bdp="$3"

    # Check if the directory has no subdirectories
    if ! find "${dir}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        local iperf_logs=(${dir}/*.iperf_output.log)
        local ver_str="before patch:"
        # Check if exactly two matching iperf logs exist
        if [ ${#iperf_logs[@]} -ne 2 ] || [ ! -e "${iperf_logs[0]}" ] || [ ! -e "${iperf_logs[1]}" ]; then
            echo "Skipping ${dir}: required iperf logs not found"
            return
        fi
        local test_logs=(${dir}/*.test.log)
        # Check if exactly two matching test logs exist
        if [ ${#test_logs[@]} -ne 2 ] || [ ! -e "${test_logs[0]}" ] || [ ! -e "${test_logs[1]}" ]; then
            echo "Skipping ${dir}: required test logs not found"
            return
        fi
        if grep -q "dirty" "${test_logs[0]}" && grep -q "dirty" "${test_logs[1]}"; then
            ver_str="after patch:"
        fi
        
        # Extract prefixes
        local src1 src2
        src1=$(basename "${test_logs[0]}" | cut -d. -f1)
        src2=$(basename "${test_logs[1]}" | cut -d. -f1)
        
        local flow1_summary=$(grep "<->" "${test_logs[0]}" | awk '{$1=$1; print}')
        if [ -z "${flow1_summary+x}" ]; then
            return
        elif [ -z "${flow1_summary}" ]; then
            return
        fi
        local flow2_summary=$(grep "<->" "${test_logs[1]}" | awk '{$1=$1; print}')
        if [ -z "${flow2_summary+x}" ]; then
            return
        elif [ -z "${flow2_summary}" ]; then
            return
        fi

        local flow1_id=$(echo "${flow1_summary}" | awk -F'id:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow1_plot="${dir}/${src1}.${flow1_id}.txt"
        local flow2_id=$(echo "${flow2_summary}" | awk -F'id:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow2_plot="${dir}/${src2}.${flow2_id}.txt"

        # Check if the two plot data files exist
        if [ ! -e "${flow1_plot}" ] || [ ! -e "${flow2_plot}" ]; then
            echo "Skipping ${dir}: required plot data files not found"
            return
        fi

        local flow1_stack=$(echo "${flow1_summary}" | awk -F'stack:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow1_cc=$(echo "${flow1_summary}" | awk -F'tcp_cc:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow1_srtt_stats=$(grep "avg_srtt:" "${test_logs[0]}" | awk '{$1=$1; print}')
        local flow1_srtt_stats="${flow1_srtt_stats//_/\\\\\\_}"
        local flow1_max_cwnd=$(grep "max_cwnd:" "${test_logs[0]}" | awk '{printf "%d\n", $6}')
        
        local flow2_stack=$(echo "${flow2_summary}" | awk -F'stack:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow2_cc=$(echo "${flow2_summary}" | awk -F'tcp_cc:[[:space:]]*' '{print $2}' | awk '{print $1}')
        local flow2_srtt_stats=$(grep "avg_srtt:" "${test_logs[1]}" | awk '{$1=$1; print}')
        local flow2_srtt_stats="${flow2_srtt_stats//_/\\\\\\_}"
        local flow2_max_cwnd=$(grep "max_cwnd:" "${test_logs[1]}" | awk '{printf "%d\n", $6}')

        local max_cwnd=$(echo "$flow1_max_cwnd $flow2_max_cwnd" | awk '{print ($1 > $2) ? $1 : $2}')
        local ymax_cwnd=$(echo "${max_cwnd} * 1.25" | bc)

        [ "${flow1_stack}" = "${flow2_stack}" ] || { echo "Assertion failed: ${flow1_stack} != ${flow2_stack}"; exit 1; }
        [ "${flow1_cc}" = "${flow2_cc}" ] || { echo "Assertion failed: ${flow1_cc} != ${flow2_cc}"; exit 1; }
        
        local stack="rack"
        if [[ "${flow1_stack}" == "fbsd" ]]; then
            stack="freebsd"
        fi
        local cc_algo=$(echo "$flow1_cc" | tr 'A-Z' 'a-z')      ## lower case
        local output_file="all_cwnd_chart_${sec}.pdf"
        local cwnd_output="${dir}/${output_file}"
        echo "generating gnuplot figure ${output_file}"

        cwnd_title_str="${ver_str} ${stack} stack ${cc_algo} congestion window ${bdp}"
        local pt_interval=$((sec * 10))

gnuplot -persist <<EOF
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 8in,6in background rgb "white"
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative
set xtics nomirror
set ytics nomirror
set tmargin 3       # Top margin
set mxtics
set autoscale fix
set xlabel "time (second)"
set xrange [0:${sec}]

# first plot cwnd
set title "${cwnd_title_str}"
set output "${cwnd_output}"
set ylabel "cwnd (byte)"
set yrange [0:${ymax_cwnd}]
# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval ${pt_interval}
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval ${pt_interval}

plot "${flow1_plot}" using 2:3 title "flow1: ${flow1_srtt_stats}" with linespoints ls 1, \
     "${flow2_plot}" using 2:3 title "flow2: ${flow2_srtt_stats}" with linespoints ls 2
EOF
    fi
}

if [  $# -ne 2 ]; then
    echo -e "\nUsage:\n$0 <comment>\n example: bash $0 300 'under 0.27%BDP bottleneck buffer'\n"
    exit 1
fi

seconds=$1
bdp_comment=$2
bdp_comment="${bdp_comment//_/\\\\\\_}"

# Starting point (you can set this to any path)
root_dir="."

# Find all directories and apply the function
find "$root_dir" -type d | while read -r dir; do
    echo -e "under ${dir}:"
    generate_thruput_plot_if_leaf "$dir" "${seconds}" "${bdp_comment}"
    generate_cwnd_plot_if_leaf "$dir" "${seconds}" "${bdp_comment}"
done
