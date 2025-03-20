#! /bin/bash

display_usage() {
	echo -e "\nUsage:\n$0 file1 [file2 file3...]"
}

# if less than one arguments supplied, display usage
if [  $# -lt 1 ]
then
	echo "not enough input arguments"
	display_usage
	exit 1
fi

echo "generating gnuplot figure..."
gnuplot -persist << EOF

set title "congestion window (cwnd) chart" offset 0.0,-0.5
set xlabel "time (second)" offset 0.0,0.5
set ylabel "cwnd (byte)" offset 0,0.0
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics

set xrange [0:100]
set yrange [0:8000000]
set autoscale fix

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 10000
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 10000
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 10000
set style line 4 lc rgb 'magenta' lt 1 lw 2 pt 4 pointsize 1 pointinterval 1000
set style line 5 lc rgb '#7F7F7F' lt 3 lw 1 	# dashline gray pointinterval 10

set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative
set term pdfcairo color lw 1 dashlength 1 enhanced font "Courier New,16" dashed size 8in,6in background rgb "white"
set output "cwnd_chart.pdf"

#plot "$1" using 2:3 title "FreeBSD default stack CUBIC" with linespoints ls 1, \
#	 "$2" using 2:3  title "FreeBSD RACK stack CUBIC" with linespoints ls 2, \
#	 "$3" using 1:3  title "Linux CUBIC" with linespoints ls 3, \
#	 "$4" using 1:3  title "Linux NewReno" with linespoints ls 4

plot "$1" using 2:3 title "FreeBSD default stack CUBIC" with linespoints ls 1
#plot "$1" using 2:3 title "FreeBSD RACK stack CUBIC" with linespoints ls 1
#plot "$1" using 1:3 title "Linux stock CUBIC" with linespoints ls 1


#plot "$1" using 2:3 title "FreeBSD RACK stack cwnd" with linespoints ls 1, \
#	 "$1" using 2:10 title "FreeBSD RACK stack w\\\_cubic" with linespoints ls 2, \
#	 "$1" using 2:9 title "FreeBSD RACK stack w\\\_newreno" with linespoints ls 3

EOF


