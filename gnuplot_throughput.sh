#! /bin/bash

# if less than one arguments supplied, display usage
if [  $# -lt 1 ]
then
    echo "not enough input arguments"
    echo -e "\nUsage:\n$0 n1.mbps_timeline n2.mbps_timeline n1.avg.goodput n2.avg.goodput seconds"
    exit 1
fi

file1=$1
file2=$2
file1_avg_thruput=$3
file2_avg_thruput=$4
seconds=$5

agg_mbps="aggregated_time_mbps.txt"
awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}' \
            ${file1} ${file2} > ${agg_mbps}
max_thruput_timeline=$(awk 'BEGIN {max = 0} {if ($2 > max) max = $2} END {print max}'\
                     ${agg_mbps})
ymax_thruput=$(echo "${max_thruput_timeline} * 1.4" | bc)

echo "generating gnuplot figure..."
gnuplot -persist << EOF

set output "all_throughput_chart.pdf"
set title "throughput chart" offset 0.0,-0.5
set xlabel "time (second)" offset 0.0,0.5
set ylabel "throughput (Mbits/sec)" offset 0,0.0
set xtics nomirror
set ytics nomirror
set tmargin 3       # Top margin
set mxtics

set xrange [0:${seconds}]
set yrange [0:${ymax_thruput}]
set autoscale fix

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 1
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 1
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 1
set style line 4 lc rgb 'magenta' lt 1 lw 2 pt 4 pointsize 1 pointinterval 1
# dashline gray
set style line 5 lc rgb '#7F7F7F' lt 3 lw 1 pointinterval 5

set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16"\
    dashed size 8in,6in background rgb "white"

f1_avg = real(system("awk '{print}' ${file1_avg_thruput}"))
f2_avg = real(system("awk '{print}' ${file2_avg_thruput}"))
link_avg = (f1_avg + f2_avg)
plot "${file1}" using 1:2 title sprintf("snd1: average throughput = %.1f Mbits/sec",\
                f1_avg) with linespoints ls 1,\
     "${file2}" using 1:2 title sprintf("snd2: average throughput = %.1f Mbits/sec",\
                f2_avg) with linespoints ls 2,\
     "${agg_mbps}" using 1:2 with linespoints ls 3 \
                   title sprintf("aggregated throughput: average link utilization = %.1f Mbits/sec", link_avg)
EOF
