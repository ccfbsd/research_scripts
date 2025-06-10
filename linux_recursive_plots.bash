#!/bin/bash

# Define a function to check if a folder is a leaf and generate a log
generate_thruput_plot_if_leaf() {
    local dir="$1"
    local sec="$2"
    local bdp="$3"

    # Check if the directory has no subdirectories
    if ! find "${dir}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        local iperf_logs=(${dir}/*.iperf_output.log)
        # Check if exactly two matching iperf logs exist
        if [ ${#iperf_logs[@]} -ne 2 ] || [ ! -e "${iperf_logs[0]}" ] || [ ! -e "${iperf_logs[1]}" ]; then
            echo "Skipping ${dir}: required iperf logs not found"
            return
        fi

        # Extract prefixes
        local src1 src2
        src1=$(basename "${iperf_logs[0]}" | cut -d. -f1)
        src2=$(basename "${iperf_logs[1]}" | cut -d. -f1)
        
        local flow1_cc=$(grep "TCP congestion control set to" "${iperf_logs[0]}" | awk '{printf "%s\n", $6}')
        local flow2_cc=$(grep "TCP congestion control set to" "${iperf_logs[1]}" | awk '{printf "%s\n", $6}')
        [ "${flow1_cc}" = "${flow2_cc}" ] || { echo "Assertion failed: ${flow1_cc} != ${flow2_cc}"; exit 1; }
        local cc_algo=$(echo "$flow1_cc" | tr 'A-Z' 'a-z')      ## lower case

        local n1_mbps="${dir}/${src1}.mbps_timeline.txt"
        local n2_mbps="${dir}/${src2}.mbps_timeline.txt"

        local n1_avg="${dir}/${src1}.avg.goodput"
        local n2_avg="${dir}/${src2}.avg.goodput"
        local agg_mbps="${dir}/aggregated_time_mbps.txt"
        awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}' ${n1_mbps} ${n2_mbps} > ${agg_mbps}
        
        local output_file="all_throughput_chart_${sec}.pdf"
        local thruput_output="${dir}/${output_file}"
        echo "generating gnuplot figure ${output_file}"

        throughput_title_str="Linux ${cc_algo} throughput ${bdp}"

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

f1_avg = real(system("awk '{print}' ${n1_avg}"))
f2_avg = real(system("awk '{print}' ${n2_avg}"))
link_avg = (f1_avg + f2_avg)
plot "${n1_mbps}" using 1:2 title sprintf("flow1: average throughput = %.1f Mbits/sec", f1_avg) with linespoints ls 1, \
     "${n2_mbps}" using 1:2 title sprintf("flow2: average throughput = %.1f Mbits/sec", f2_avg) with linespoints ls 2, \
     "${agg_mbps}" using 1:2 title sprintf("aggregated throughput: average link utilization = %.1f Mbits/sec", link_avg) with linespoints ls 3
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
        # Check if exactly two matching iperf logs exist
        if [ ${#iperf_logs[@]} -ne 2 ] || [ ! -e "${iperf_logs[0]}" ] || [ ! -e "${iperf_logs[1]}" ]; then
            echo "Skipping ${dir}: required iperf logs not found"
            return
        fi

        # Extract prefixes
        local src1 src2
        src1=$(basename "${iperf_logs[0]}" | cut -d. -f1)
        src2=$(basename "${iperf_logs[1]}" | cut -d. -f1)

        local flow1_cc=$(grep "TCP congestion control set to" "${iperf_logs[0]}" | awk '{printf "%s\n", $6}')
        local flow2_cc=$(grep "TCP congestion control set to" "${iperf_logs[1]}" | awk '{printf "%s\n", $6}')
        [ "${flow1_cc}" = "${flow2_cc}" ] || { echo "Assertion failed: ${flow1_cc} != ${flow2_cc}"; exit 1; }
        local cc_algo=$(echo "$flow1_cc" | tr 'A-Z' 'a-z')      ## lower case
        
        local flow1_plot="${dir}/${src1}.plot.txt"
        local flow2_plot="${dir}/${src2}.plot.txt"

        # Check if the two plot data files exist
        if [ ! -e "${flow1_plot}" ] || [ ! -e "${flow2_plot}" ]; then
            echo "Skipping ${dir}: required plot data files not found"
            return
        fi

        local n1_mbps="${dir}/${src1}.mbps_timeline.txt"
        local n2_mbps="${dir}/${src2}.mbps_timeline.txt"

        read f1_min_cwnd f1_avg_cwnd f1_max_cwnd f1_min_srtt f1_avg_srtt f1_max_srtt <<< $(awk '
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
            print min_cwnd, int(cwnd_sum/count), max_cwnd, min_srtt, int(srtt_sum/count), max_srtt
        }' "${flow1_plot}")

        read f2_min_cwnd f2_avg_cwnd f2_max_cwnd f2_min_srtt f2_avg_srtt f2_max_srtt <<< $(awk '
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
            print min_cwnd, int(cwnd_sum/count), max_cwnd, min_srtt, int(srtt_sum/count), max_srtt
        }' "${flow2_plot}")

        local max_cwnd=$(echo "$f1_max_cwnd $f2_max_cwnd" | awk '{print ($1 > $2) ? $1 : $2}')
        ymax_cwnd=$(echo "$max_cwnd * 1.25" | bc)

        local flow1_srtt_stats="avg\\\_srtt: ${f1_avg_srtt}, min\\\_srtt: ${f1_min_srtt}, max\\\_srtt: ${f1_max_srtt} µs"
        local flow2_srtt_stats="avg\\\_srtt: ${f2_avg_srtt}, min\\\_srtt: ${f2_min_srtt}, max\\\_srtt: ${f2_max_srtt} µs"

        local output_file="all_cwnd_chart_${sec}.pdf"
        local cwnd_output="${dir}/${output_file}"
        echo "generating gnuplot figure ${output_file}"

        cwnd_title_str="Linux ${cc_algo} congestion window ${bdp}"
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

plot "${flow1_plot}" using 1:3 title "flow1: ${flow1_srtt_stats}" with linespoints ls 1, \
     "${flow2_plot}" using 1:3 title "flow2: ${flow2_srtt_stats}" with linespoints ls 2
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