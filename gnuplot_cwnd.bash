#! /bin/bash

# if less than one arguments supplied, display usage
if [  $# -lt 1 ]
then
    echo "not enough input arguments"
    echo -e "\nUsage:\n$0 snd1 snd2 seconds"
    exit 1
fi

snd1=$1
snd2=$2
seconds=$3

snd1_cw="${snd1}.plot_files"
snd1_cw=$(ls ${snd1}.plot_files/*)
snd2_cw="${snd2}.plot_files"
snd2_cw=$(ls ${snd2}.plot_files/*)
#echo "snd1_cw: [${snd1_cw}], snd2_cw: [${snd2_cw}]"

snd1_log="${snd1}.test.log"
snd2_log="${snd2}.test.log"
#echo "snd1_log: [${snd1_log}], snd2_log: [${snd2_log}]"

snd1_avg="${snd1}.avg.goodput"
snd2_avg="${snd2}.avg.goodput"
#echo "snd1_avg: [${snd1_avg}], snd2_avg: [${snd2_avg}]"

snd1_mbps="${snd1}.mbps_timeline.txt"
snd2_mbps="${snd2}.mbps_timeline.txt"
#echo "snd1_mbps: [${snd1_mbps}], snd1_mbps: [${snd1_mbps}]"

agg_mbps="aggregated_time_mbps.txt"


# Extract congestion control values
cc1=$(grep 'net.ipv4.tcp_congestion_control' "${snd1_log}" | awk -F'=' '{print $2}' | xargs)
cc2=$(grep 'net.ipv4.tcp_congestion_control' "${snd2_log}" | awk -F'=' '{print $2}' | xargs)

# Assert they are the same
if [[ "$cc1" != "$cc2" ]]; then
    echo "ERROR: Mismatch: $cc1 != $cc2"
    exit 1
fi

line=$(grep 'flowid:' ${snd1_log})
#echo "$line"
f1_avg_srtt=$(echo "$line" | rg -oP 'avg_srtt:\s*\K\d+')
f1_min_srtt=$(echo "$line" | rg -oP 'min_srtt:\s*\K\d+')
f1_max_srtt=$(echo "$line" | rg -oP 'max_srtt:\s*\K\d+')
f1_avg_cwnd=$(echo "$line" | rg -oP 'avg_cwnd:\s*\K\d+')
f1_min_cwnd=$(echo "$line" | rg -oP 'min_cwnd:\s*\K\d+')
f1_max_cwnd=$(echo "$line" | rg -oP 'max_cwnd:\s*\K\d+')

#echo "[${f1_avg_srtt} ${f1_min_srtt} ${f1_max_srtt} ${f1_avg_cwnd} ${f1_min_cwnd} ${f1_max_cwnd}]"
flow1_srtt_stats="avg\\\_srtt: ${f1_avg_srtt}, min\\\_srtt: ${f1_min_srtt}, max\\\_srtt: ${f1_max_srtt} µs"

line=$(grep 'flowid:' ${snd2_log})
#echo "$line"
f2_avg_srtt=$(echo "$line" | rg -oP 'avg_srtt:\s*\K\d+')
f2_min_srtt=$(echo "$line" | rg -oP 'min_srtt:\s*\K\d+')
f2_max_srtt=$(echo "$line" | rg -oP 'max_srtt:\s*\K\d+')
f2_avg_cwnd=$(echo "$line" | rg -oP 'avg_cwnd:\s*\K\d+')
f2_min_cwnd=$(echo "$line" | rg -oP 'min_cwnd:\s*\K\d+')
f2_max_cwnd=$(echo "$line" | rg -oP 'max_cwnd:\s*\K\d+')

#echo "[${f2_avg_srtt} ${f2_min_srtt} ${f2_max_srtt} ${f2_avg_cwnd} ${f2_min_cwnd} ${f2_max_cwnd}]"
flow2_srtt_stats="avg\\\_srtt: ${f2_avg_srtt}, min\\\_srtt: ${f2_min_srtt}, max\\\_srtt: ${f2_max_srtt} µs"

max_cwnd_global=$(echo "$f1_max_cwnd $f2_max_cwnd" | awk '{print ($1 > $2) ? $1 : $2}')

awk 'NR==FNR {data[int($1)]=$2; next} {print int($1), data[int($1)] + $2}' \
            ${snd1_mbps} ${snd2_mbps} > ${agg_mbps}
max_thruput_timeline=$(awk 'BEGIN {max = 0} {if ($2 > max) max = $2} END {print max}'\
                     ${agg_mbps})
ymax_thruput=$(echo "${max_thruput_timeline} * 1.4" | bc)
ymax_cwnd=$(echo "${max_cwnd_global} * 1.4" | bc)
#echo "ymax_cwnd: [${ymax_cwnd}], ymax_thruput: [${ymax_thruput}]"

cwnd_title_str="cwnd chart"
throughput_title_str="throughput chart"
pt_interval=$((seconds * 100))

echo "generating gnuplot figure..."
gnuplot -persist << EOF

set output "all_cwnd_thruput.pdf"
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 enhanced font "DejaVu Sans Mono,16"\
    dashed size 12in,9in background rgb "white"
set multiplot layout 2,1 title "TCP Analysis" offset 3.0,0.0

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

plot "${snd1_cw}" using 1:2 title "socket1: ${flow1_srtt_stats}" with linespoints ls 1,\
     "${snd2_cw}" using 1:2 title "socket2: ${flow2_srtt_stats}" with linespoints ls 2

# Second plot throughput
set title "${throughput_title_str}"
set ylabel "throughput (Mbits/sec)"
set yrange [0:${ymax_thruput}]
# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 5
set style line 2 lc rgb 'blue' lt 1 lw 2 pt 2 pointsize 1 pointinterval 5
set style line 3 lc rgb 'green' lt 1 lw 2 pt 3 pointsize 1 pointinterval 5

f1_avg = real(system("awk '{print}' ${snd1_avg}"))
f2_avg = real(system("awk '{print}' ${snd2_avg}"))
link_avg = (f1_avg + f2_avg)
plot "${snd1_mbps}" using 1:2 title sprintf("socket1: average throughput = %.1f Mbits/sec",\
                f1_avg) with linespoints ls 1,\
     "${snd2_mbps}" using 1:2 title sprintf("socket2: average throughput = %.1f Mbits/sec",\
                f2_avg) with linespoints ls 2,\
     "${agg_mbps}" using 1:2 with linespoints ls 3 \
                   title sprintf("aggregated throughput: average = %.1f Mbits/sec", link_avg)

unset multiplot
unset output
EOF
