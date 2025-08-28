#!/bin/sh
# Filename: nfs_traffic.sh
# Description: Simulate NFS traffic with Fio using realistic workloads
# Works on both FreeBSD and Linux
# Usage: ./nfs_traffic.sh workload_size [mount_point]
#   workload_size: small | medium | large | all
#   mount_point: mounted NFS directory (e.g., /mnt/nfs)

# --- Usage check first ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 {small|medium|large|all} [mount_point]"
    exit 1
fi

# -------------------------
# Input arguments
# -------------------------
WORKLOAD=$1
MNT_POINT=${2:-/mnt/nfs}   # default mount directory
HOSTNAME=$(hostname -s)

# Detect OS
OS=$(uname -s)
case "$OS" in
  FreeBSD)  IOENGINE="sync" ;;
  Linux)    IOENGINE="libaio" ;;
  *)        echo "Unsupported OS: $OS";
            exit 1 ;;
esac

# Detect node type (Linux/FreeBSD specific path, fallback unknown)
if [ -x /usr/libexec/emulab/nodetype ]; then
    NODE_TYPE=$(/usr/libexec/emulab/nodetype | awk '{print $1}')
elif [ -x /usr/local/bin/nodetype ]; then
    NODE_TYPE=$(/usr/local/etc/emulab/nodetype | awk '{print $1}')
else
    NODE_TYPE="unknown"
    echo ">>> Warning: nodetype command not found, using 'unknown'"
fi

CSV_FILE="${HOSTNAME}_${NODE_TYPE}_fio_results.csv"
LOG_FILE="${HOSTNAME}_${NODE_TYPE}_fio_results.log"

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

# Fio workload definitions
get_workload_params() {
    case $1 in
        small)  BS=8k;   FILE_SIZE=512M; RWMIX=80; IODEPTH=4;  NUMJOBS=1; RUNTIME=30 ;;
        medium) BS=64k;  FILE_SIZE=1G;   RWMIX=70; IODEPTH=8;  NUMJOBS=2; RUNTIME=60 ;;
        large)  BS=512k; FILE_SIZE=2G;   RWMIX=60; IODEPTH=16; NUMJOBS=4; RUNTIME=120 ;;
        *) echo "Unknown workload: $1"; exit 1 ;;
    esac
}

run_fio() {
    W=$1
    get_workload_params $W

    TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S_%Z')
    OUTFILE="$MNT_POINT/fio_testfile_${W}"
    JSON_FILE="fio_output_${W}.json"

    # Append to LOG_FILE
    if [ ! -f $LOG_FILE ]; then
        printf "Running NFS traffic simulation:\n" | tee ${LOG_FILE}
    else
        printf "\nRunning NFS traffic simulation:\n" | tee -a ${LOG_FILE}
    fi
    echo "Workload: $W" | tee -a $LOG_FILE
    echo "Node Type: $NODE_TYPE" | tee -a ${LOG_FILE}
    echo "Mount point: $MNT_POINT" | tee -a $LOG_FILE
    echo "Block size: $BS, File size: $FILE_SIZE, Read mix: ${RWMIX}%" | tee -a $LOG_FILE
    echo "IO depth: $IODEPTH, Num jobs: $NUMJOBS, Runtime: $RUNTIME sec" | tee -a $LOG_FILE
    echo "IO Engine: $IOENGINE" | tee -a ${LOG_FILE}
    echo "-----------------------------------------------------" | tee -a $LOG_FILE

    # Run Fio
    fio --name=test --rw=randrw --rwmixread=$RWMIX \
        --bs=$BS --size=$FILE_SIZE --ioengine=$IOENGINE \
        --iodepth=$IODEPTH --numjobs=$NUMJOBS --runtime=$RUNTIME \
        --time_based --overwrite=1 --direct=1 --filename=$OUTFILE \
        --output-format=json --output=$JSON_FILE

    # Extract raw numbers
    READ_BW=$(jq '.jobs[0].read.bw' $JSON_FILE)              # KB/s
    READ_IOPS=$(jq '.jobs[0].read.iops' $JSON_FILE)          # IOPS
    READ_LAT_US=$(jq '.jobs[0].read.lat_ns.mean' $JSON_FILE) # ns
    READ_LAT_95_US=$(jq '.jobs[0].read.clat_ns.percentile["95.000000"]' $JSON_FILE)

    WRITE_BW=$(jq '.jobs[0].write.bw' $JSON_FILE)
    WRITE_IOPS=$(jq '.jobs[0].write.iops' $JSON_FILE)
    WRITE_LAT_US=$(jq '.jobs[0].write.lat_ns.mean' $JSON_FILE)
    WRITE_LAT_95_US=$(jq '.jobs[0].write.clat_ns.percentile["95.000000"]' $JSON_FILE)

    # Convert latencies from ns to us
    READ_LAT_US=$(awk "BEGIN {printf \"%.1f\", $READ_LAT_US/1000}")
    READ_LAT_95_US=$(awk "BEGIN {printf \"%.1f\", $READ_LAT_95_US/1000}")
    WRITE_LAT_US=$(awk "BEGIN {printf \"%.1f\", $WRITE_LAT_US/1000}")
    WRITE_LAT_95_US=$(awk "BEGIN {printf \"%.1f\", $WRITE_LAT_95_US/1000}")

    # --- CSV header auto-create ---
    if [ ! -f "${CSV_FILE}" ]; then
        echo "timestamp,node_type,workload,mount_point,block_size,file_size,rwmix,read_bw_kBps,read_iops,read_lat_us,read_lat95_us,write_bw_kBps,write_iops,write_lat_us,write_lat95_us" > "${CSV_FILE}"
    fi

    # ---- CSV output (raw numbers, no units) ----
    echo "$TIMESTAMP,$NODE_TYPE,$W,$MNT_POINT,$BS,$FILE_SIZE,$RWMIX,$READ_BW,$READ_IOPS,$READ_LAT_US,$READ_LAT_95_US,$WRITE_BW,$WRITE_IOPS,$WRITE_LAT_US,$WRITE_LAT_95_US" >> $CSV_FILE

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
    echo "-----------------------------------------------------" | tee -a $LOG_FILE
}

if [ "$WORKLOAD" = "all" ]; then
    for W in small medium large; do
        run_fio $W
        sleep 10
    done
else
    run_fio $WORKLOAD
fi