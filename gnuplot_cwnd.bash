#! /bin/bash

# if not 3 arguments supplied, display usage
if [  $# -ne 3 ]
then
	echo -e "requires 3 input arguments\nUsage: $0 n1fbsd.plot.txt n2fbsd.plot.txt 300\n"
	exit 1
fi

data1=$1
data2=$2
seconds=$3
pt_interval=$((seconds * 100))

echo "generating gnuplot figure..."
gnuplot -persist << EOF

set title "Linux stack CUBIC congestion window chart"
set output "cwnd_chart.pdf"
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16" dashed size 8in,6in background rgb "white"
set xlabel "time (second)"
set ylabel "cwnd (byte)"
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:${seconds}]
set yrange [0:6e6]
set autoscale fix

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval ${pt_interval}
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval ${pt_interval}
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval ${pt_interval}

set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

plot "${data1}" using 1:3 title "flow1" with linespoints ls 1, \
     "${data2}" using 1:3 title "flow2" with linespoints ls 2

EOF
