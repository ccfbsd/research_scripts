#! /bin/bash

# if not 4 arguments supplied, display usage
if [  $# -ne 4 ]
then
	echo -e "requires 4 input arguments\nUsage: $0 n1.mbps_timeline n2.mbps_timeline n1.avg.goodput n2.avg.goodput\n"
	exit 1
fi

n1_mbps_timeline=$1
n2_mbps_timeline=$2
n1_avg_goodput=$3
n2_avg_goodput=$4
agg_time_mbps=aggregated_time_mbps.txt
awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}' ${n1_mbps_timeline} ${n2_mbps_timeline} > ${agg_time_mbps}
echo "generating gnuplot figure..."

gnuplot -persist << EOF

set title "Linux stack CUBIC throughput chart" offset 0.0,-0.5
set output "agg_throughput_chart.pdf"
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 8in,6in background rgb "white"
set xlabel "time (second)" offset 0.0,0.5
set ylabel "throughput (Mbits/sec)" offset 0,0.0
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:3e2]
set yrange [0:10e2]
set autoscale fix

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 4
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 4
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 4
set style line 4 lc rgb 'magenta' lt 1 lw 2 pt 4 pointsize 1 pointinterval 4
set style line 5 lc rgb '#7F7F7F' lt 3 lw 1 pointinterval 5                   # dashline gray
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

f1_avg_goodput = real(system("awk '{print}' ${n1_avg_goodput}"))
f2_avg_goodput = real(system("awk '{print}' ${n2_avg_goodput}"))
plot "${n1_mbps_timeline}" using 1:2 title sprintf("flow1: average throughput = %.1f Mbits/sec", f1_avg_goodput) with linespoints ls 1, \
     "${n2_mbps_timeline}" using 1:2 title sprintf("flow2: average throughput = %.1f Mbits/sec", f2_avg_goodput) with linespoints ls 2, \
     "${agg_time_mbps}" using 1:2 title sprintf("aggregated throughput: average link utilization = %.1f Mbits/sec", (f1_avg_goodput + f2_avg_goodput)) with linespoints ls 3
EOF
