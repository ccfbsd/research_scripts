#!/bin/sh
# Filename: nfs_traffic.sh
# Description: Simulate NFS traffic with fio using realistic workloads
# Usage: ./nfs_traffic.sh workload_size [mount_point]
#   workload_size: small | medium | large
#   mount_point: mounted NFS directory (e.g., /mnt/nfs)

# --- Usage check first ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 small [mount_point]"
    exit 1
fi

# -------------------------
# Input arguments
# -------------------------
WORKLOAD=$1
MNT_POINT=${2:-/mnt/nfs}   # default mount directory
TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S %Z')
CSV_FILE="nfs_traffic_summary.${WORKLOAD}.csv"
OUTFILE="$MNT_POINT/fio_testfile_$WORKLOAD"
JSON_FILE="fio_output_${WORKLOAD}.json"

# -------------------------
# Helper functions
# -------------------------

# Convert KB/s to human-readable units
human_bw() {
    val=$1
    awk -v v="$val" 'BEGIN {
        if (v >= 1048576) printf "%.1f GB/s", v/1048576;
        else if (v >= 1024) printf "%.1f MB/s", v/1024;
        else printf "%.0f KB/s", v;
    }'
}

# Convert IOPS to readable form (just round)
human_iops() {
    val=$1
    awk -v v="$val" 'BEGIN {
        if (v >= 1000) printf "%.1f KIOPS", v/1000;
        else printf "%.1f", v;
    }'
}

# Convert latency (μs) to ms if big
human_lat() {
    val=$1
    awk -v v="$val" 'BEGIN {
        if (v >= 1000.0) printf "%.1f ms", v/1000.0;
        else printf "%.1f us", v;
    }'
}

# Detect OS
OS=$(uname -s)
case "$OS" in
  FreeBSD)
    IOENGINE="sync"
    NODETYPE_CMD="/usr/local/etc/emulab/nodetype"
    ;;
  Linux)
    IOENGINE="libaio"
    NODETYPE_CMD="/usr/libexec/emulab/nodetype"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

if [ -x "$NODETYPE_CMD" ]; then
    NODE_TYPE=$($NODETYPE_CMD)
else
    NODE_TYPE="unknown"
fi

# Workload profiles
case "$WORKLOAD" in
  small)
    BS=8k;   FILE_SIZE=512M; RWMIX=80; IODEPTH=4;  NUMJOBS=1; RUNTIME=30 ;;
  medium)
    BS=64k;  FILE_SIZE=1G;   RWMIX=70; IODEPTH=8;  NUMJOBS=2; RUNTIME=60 ;;
  large)
    BS=256k; FILE_SIZE=2G;   RWMIX=60; IODEPTH=16; NUMJOBS=4; RUNTIME=120 ;;
  *)
    echo "Unknown workload: $WORKLOAD"; exit 1 ;;
esac

LOG_FILE="${NODE_TYPE}_fio_${WORKLOAD}.log"

# Append to LOG_FILE
if [ ! -f $LOG_FILE ]; then
    printf "Running NFS traffic simulation:\n" | tee ${LOG_FILE}
else
    printf "\nRunning NFS traffic simulation:\n" | tee -a ${LOG_FILE}
fi

echo "Workload: $WORKLOAD" | tee -a ${LOG_FILE}
echo "Node Type: $NODE_TYPE" | tee -a ${LOG_FILE}
echo "Mount point: $MNT_POINT" | tee -a ${LOG_FILE}
echo "Block size: $BS, File size: $FILE_SIZE, Read mix: $RWMIX%" | tee -a ${LOG_FILE}
echo "IO depth: $IODEPTH, Num jobs: $NUMJOBS, Runtime: $RUNTIME sec" | tee -a ${LOG_FILE}
echo "IO Engine: $IOENGINE" | tee -a ${LOG_FILE}
echo "-----------------------------------------------------" | tee -a ${LOG_FILE}

# Run fio
fio --name=test --rw=randrw --rwmixread=$RWMIX \
    --bs=$BS --size=$FILE_SIZE --ioengine=$IOENGINE \
    --iodepth=$IODEPTH --numjobs=$NUMJOBS --runtime=$RUNTIME \
    --time_based --filename=$OUTFILE \
    --output-format=json --output=$JSON_FILE

if [ $? -ne 0 ]; then
    echo "FIO test failed, skipping CSV append."
    exit 1
fi

# Parse JSON output
READ_BW=$(jq '.jobs[0].read.bw' $JSON_FILE)
WRITE_BW=$(jq '.jobs[0].write.bw' $JSON_FILE)
READ_IOPS=$(jq '.jobs[0].read.iops' $JSON_FILE)
WRITE_IOPS=$(jq '.jobs[0].write.iops' $JSON_FILE)
READ_LAT_NS=$(jq '.jobs[0].read.lat_ns.mean' $JSON_FILE)
WRITE_LAT_NS=$(jq '.jobs[0].write.lat_ns.mean' $JSON_FILE)
READ_LAT_95_NS=$(jq '.jobs[0].read.clat_ns.percentile["95.000000"]' $JSON_FILE)
WRITE_LAT_95_NS=$(jq '.jobs[0].write.clat_ns.percentile["95.000000"]' $JSON_FILE)

# Convert latency to μs
READ_LAT_US=$(awk "BEGIN {printf \"%.1f\", $READ_LAT_NS/1000}")
WRITE_LAT_US=$(awk "BEGIN {printf \"%.1f\", $WRITE_LAT_NS/1000}")
READ_LAT_95_US=$(awk "BEGIN {printf \"%.1f\", $READ_LAT_95_NS/1000}")
WRITE_LAT_95_US=$(awk "BEGIN {printf \"%.1f\", $WRITE_LAT_95_NS/1000}")

# Format human-readable values
HR_READ_BW=$(human_bw $READ_BW)
HR_WRITE_BW=$(human_bw $WRITE_BW)
HR_READ_IOPS=$(human_iops $READ_IOPS)
HR_WRITE_IOPS=$(human_iops $WRITE_IOPS)
HR_READ_LAT=$(human_lat $READ_LAT_US)
HR_WRITE_LAT=$(human_lat $WRITE_LAT_US)
HR_READ_LAT_95=$(human_lat $READ_LAT_95_US)
HR_WRITE_LAT_95=$(human_lat $WRITE_LAT_95_US)

# Display summary
echo "Simulation finished. Results:" | tee -a ${LOG_FILE}
echo "Timestamp:   $TIMESTAMP" | tee -a ${LOG_FILE}
echo "Read:  BW=$HR_READ_BW, IOPS=$HR_READ_IOPS, Avg Lat=$HR_READ_LAT, 95th Lat=$HR_READ_LAT_95" | tee -a ${LOG_FILE}
echo "Write: BW=$HR_WRITE_BW, IOPS=$HR_WRITE_IOPS, Avg Lat=$HR_WRITE_LAT, 95th Lat=$HR_WRITE_LAT_95" | tee -a ${LOG_FILE}
printf -- "-----------------------------------------------------\n" | tee -a ${LOG_FILE}

# Append to CSV (human-readable)
if [ ! -f $CSV_FILE ]; then
    echo "timestamp,node_type,workload,mount_point,block_size,file_size,read_mix,read_bw,read_iops,read_lat,read_lat_95,write_bw,write_iops,write_lat,write_lat_95" > $CSV_FILE
fi

echo "$TIMESTAMP,$NODE_TYPE,$WORKLOAD,$MNT_POINT,$BS,$FILE_SIZE,$RWMIX,$HR_READ_BW,$HR_READ_IOPS,$HR_READ_LAT,$HR_READ_LAT_95,$HR_WRITE_BW,$HR_WRITE_IOPS,$HR_WRITE_LAT,$HR_WRITE_LAT_95" >> $CSV_FILE

# Cleanup
rm -f $OUTFILE
echo "Test file $OUTFILE removed."