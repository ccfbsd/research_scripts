#!/bin/bash

if [  $# -ne 1 ]; then
    echo -e "\nUsage:\n$0 <trace_file> \n example: bash $0 s1.trace\n"
    exit 1
fi

trace_name=$1                       # linux/tcp_probe file in ftrace/perf format
plot_file=${trace_name}.plot

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

rm ${trace_name}.tmp.txt

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

duration=$(awk 'END { print $1 }' "${plot_file}")
ymax_cwnd=$(echo "$max_cwnd * 1.25" | bc)
ymax_srtt=$(echo "$max_srtt * 1.25" | bc)
cwnd_stats="avg\\\_cwnd: ${avg_cwnd}, min\\\_cwnd: ${min_cwnd}, max\\\_cwnd: ${max_cwnd} bytes"
srtt_stats="avg\\\_srtt: ${avg_srtt}, min\\\_srtt: ${min_srtt}, max\\\_srtt: ${max_srtt} µs"

echo "generating gnuplot figure..."

cwnd_title_str="${src} ${name} cwnd chart"
srtt_title_str="${src} ${name} srtt chart"

gnuplot -persist << EOF
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 12in,9in background rgb "white"
set output "${trace_name}.cwnd_srtt.pdf"
set multiplot layout 2,1 title "Flow Analysis" offset 4.0,0.0

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 100

# First plot cwnd
set title "${cwnd_title_str}"
set xlabel "time (second)"
set ylabel "cwnd (byte)"
set xtics nomirror
set ytics nomirror
set tmargin 3       # Top margin
set mxtics
set xrange [0:${duration}]
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
set tmargin 3       # Top margin
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
