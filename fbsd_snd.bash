#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

SIFTR2_NAME="siftr2.ko"  # Module name
SIFTR2_PATH="/root/siftr2"	# Module location

# Check if the module is already loaded
if ! kldstat | grep -q "$SIFTR2_NAME"; then
    echo "Module $SIFTR2_NAME is not loaded. Loading it now..."
    
    # Try loading the module
    if kldload ${SIFTR2_PATH}/${SIFTR2_NAME}; then
        echo "Module $SIFTR2_NAME loaded successfully."
    else
        echo "Failed to load module $SIFTR2_NAME. Check if the module exists or requires dependencies."
        exit 1
    fi
else
    echo "Module $SIFTR2_NAME is already loaded."
fi

log_review_tool="/root/review_siftr2_log/review_siftr2_log"
if [[ -f "${log_review_tool}" && -x "${log_review_tool}" ]]; then
    echo "${log_review_tool} exists and is executable."
else
    echo "${log_review_tool} does not exist or is not executable."
    exit 1
fi

dir=$(pwd)
tcp_port=54321
log_name=${dir}/${src}.test.log
siftr_name=${src}.${name}.siftr2
netstat_file_name=${dir}/${src}.${name}.netstat
iperf_log_name=${dir}/${src}.iperf3_output.log
throughput_timeline=${dir}/${src}.mbps_timeline.txt
snd_avg_goodput=${dir}/${src}.avg.goodput
tmp_name=${dir}/${src}.tmp.log

sysctl net.inet.tcp.functions_default | tee ${log_name}
# Don't cache ssthresh from previous connection
sysctl net.inet.tcp.hostcache.enable=0 | tee -a ${log_name}
# force to close the control socket after 4 seconds
sysctl net.inet.tcp.msl=2000 | tee -a ${log_name}
sysctl net.inet.tcp.cc.algorithm=${name} | tee -a ${log_name}
sysctl net.inet.siftr2.port_filter=${tcp_port} | tee -a ${log_name}
sysctl net.inet.siftr2.cwnd_filter=1 | tee -a ${log_name}
sysctl net.inet.siftr2.ppl=1 | tee -a ${log_name}
sysctl net.inet.siftr2.logfile=/var/log/${siftr_name} | tee -a ${log_name}
netstat -sz > /dev/null 2>&1
sysctl net.inet.siftr2.enabled=1 | tee -a ${log_name}

iperf3 -B ${src} --cport ${tcp_port} -c ${dst} -p 5201 -l 1M -t ${seconds} -i 1 -f m -VC ${name} > ${iperf_log_name}
sysctl net.inet.siftr2.enabled=0 | tee -a ${log_name}
netstat -sp tcp > ${netstat_file_name}

sleep 1

grep -E -A 2 "Summary Results" ${iperf_log_name} | grep "sender" | awk '{printf "%.2f\n", $7}' > ${snd_avg_goodput}

awk '/sec/ {split($3, interval, "-"); printf "%d\t%s\n", int(interval[2]), $7}' ${iperf_log_name} > ${tmp_name}
sed '1d' ${tmp_name} | sed '$d' | sed '$d' > ${throughput_timeline}

# Run the binary and extract the flow_id value
siftr2_log_abs_path=$(realpath /var/log/${siftr_name})
flow_id=$(${log_review_tool} -f "${siftr2_log_abs_path}" | awk -F'id:' '{print $2}' | awk '{print $1}' | tr -d '\r\n')
${log_review_tool} -f "${siftr2_log_abs_path}" -p "${src}" -s "${flow_id}" >> "${log_name}" 2>&1

cwnd_stats=$(grep "avg_cwnd:" "${log_name}" | awk '{$1=$1; print}')
#echo "[${cwnd_stats}]"
srtt_stats=$(grep "avg_srtt:" "${log_name}" | awk '{$1=$1; print}')
#echo "[${srtt_stats}]"

max_cwnd=$(grep "max_cwnd" "${log_name}" | awk '{printf "%d\n", $6}')
ymax_cwnd=$(echo "$max_cwnd * 1.25" | bc)
max_srtt=$(grep "max_srtt" "${log_name}" | awk '{printf "%d\n", $6}')
ymax_srtt=$(echo "$max_srtt * 1.25" | bc)
#echo "[${max_cwnd}][${ymax_cwnd}]"
#echo "[${max_srtt}][${ymax_srtt}]"

plot_file=${src}.${flow_id}.txt

ls -lh "${siftr2_log_abs_path}" | tee -a ${log_name}
ls -lh "${plot_file}" | tee -a ${log_name}
tar -zcf ${siftr_name}.tgz -C /var/log ${siftr_name}
rm ${siftr2_log_abs_path} ${tmp_name}

echo "generating gnuplot figure..."

cwnd_title_str="${src} ${name} cwnd chart"
srtt_title_str="${src} ${name} srtt chart"

gnuplot -persist << EOF
set encoding utf8
set term pdfcairo color lw 1 dashlength 1 noenhanced font "DejaVu Sans Mono,16" dashed size 12in,9in background rgb "white"
set output "${src}.cwnd_srtt.${flow_id}.pdf"
set multiplot layout 2,1 title "Flow Analysis" offset 4.0,0.0

# linecolor(lc), linetype(lt), linewidth(lw), dashtype(dt), pointtype(pt)
set style line 1 lc rgb 'red' lt 1 lw 2 pt 1 pointsize 1 pointinterval 1000

# First plot cwnd
set title "${cwnd_title_str}" offset 0.0,-0.5
set xlabel "time (second)" offset 0.0,0.5
set ylabel "cwnd (byte)" offset 0,0.0
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:${seconds}]
set yrange [0:${ymax_cwnd}]
set autoscale fix
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

plot "${plot_file}" using 2:3 title "flow1: ${cwnd_stats}" with linespoints ls 1

# Second plot
set title "${srtt_title_str}" offset 0.0,-0.5
set xlabel "time (second)" offset 0.0,0.5
set ylabel "srtt (microsecond)" offset 0,0
set xtics nomirror
set ytics nomirror
set tmargin 3		# Top margin
set mxtics
set xrange [0:${seconds}]
set yrange [0:${ymax_srtt}]
set autoscale fix
set key box opaque vertical right top reverse Left samplen 2 width 1 spacing 1.5
set boxwidth 2 relative

plot "${plot_file}" using 2:5 title "flow1: ${srtt_stats}" with linespoints ls 1

unset multiplot
unset output
EOF
