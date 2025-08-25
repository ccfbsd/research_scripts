#!/bin/sh
# Filename: nfs_traffic.sh
# Description: Simulate NFS traffic with fio using realistic workloads
# Usage: ./nfs_traffic.sh <workload_size> <mount_point>
#   workload_size: small | medium | large
#   mount_point: mounted NFS directory (e.g., /mnt/nfs)

# -------------------------
# Input arguments
# -------------------------
WORKLOAD=$1
MNT_POINT=${2:-/mnt/nfs}   # default mount directory
TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S')
CSV_FILE="nfs_traffic_summary.${WORKLOAD}.csv"
OUTFILE="$MNT_POINT/fio_testfile_$WORKLOAD"
JSON_FILE="fio_output_${WORKLOAD}.json"

# Define workload parameters
case "$WORKLOAD" in
  small)
    BS=8k
    FILE_SIZE=512M
    RWMIX=80
    IODEPTH=4
    NUMJOBS=1
    RUNTIME=30
    ;;
  medium)
    BS=64k
    FILE_SIZE=2G
    RWMIX=70
    IODEPTH=8
    NUMJOBS=2
    RUNTIME=60
    ;;
  large)
    BS=256k
    FILE_SIZE=8G
    RWMIX=60
    IODEPTH=16
    NUMJOBS=4
    RUNTIME=120
    ;;
  *)
    echo "Unknown workload: $WORKLOAD"
    exit 1
    ;;
esac

echo "Running NFS traffic simulation:"
echo "Workload: $WORKLOAD"
echo "Mount point: $MNT_POINT"
echo "Block size: $BS, File size: $FILE_SIZE, Read mix: $RWMIX%"
echo "IO depth: $IODEPTH, Num jobs: $NUMJOBS, Runtime: $RUNTIME sec"
echo "-----------------------------------------------------"

# Run FIO
fio --name=test --rw=randrw --rwmixread=$RWMIX \
    --bs=$BS --size=$FILE_SIZE --ioengine=sync \
    --iodepth=$IODEPTH --numjobs=$NUMJOBS --runtime=$RUNTIME \
    --time_based --filename=$OUTFILE \
    --output-format=json --output=$JSON_FILE

# Parse JSON output
READ_BW=$(jq '.jobs[0].read.bw' $JSON_FILE)
WRITE_BW=$(jq '.jobs[0].write.bw' $JSON_FILE)
READ_IOPS=$(jq '.jobs[0].read.iops' $JSON_FILE)
WRITE_IOPS=$(jq '.jobs[0].write.iops' $JSON_FILE)
READ_LAT_NS=$(jq '.jobs[0].read.lat_ns.mean' $JSON_FILE)
WRITE_LAT_NS=$(jq '.jobs[0].write.lat_ns.mean' $JSON_FILE)

# Convert latency to microseconds
READ_LAT_US=$(awk "BEGIN {printf \"%.2f\", $READ_LAT_NS/1000}")
WRITE_LAT_US=$(awk "BEGIN {printf \"%.2f\", $WRITE_LAT_NS/1000}")

# Display summary
echo "Simulation finished. Results:"
echo "Timestamp:   $TIMESTAMP"
echo "Read:        BW=$READ_BW KB/s, IOPS=$READ_IOPS, Lat=$READ_LAT_US us"
echo "Write:       BW=$WRITE_BW KB/s, IOPS=$WRITE_IOPS, Lat=$WRITE_LAT_US us"
echo "-----------------------------------------------------"

# Append to CSV (single line per workload)
if [ ! -f $CSV_FILE ]; then
    echo "timestamp,workload,mount_point,block_size,file_size,read_mix,read_bw_kBps,read_iops,read_lat_us,write_bw_kBps,write_iops,write_lat_us" > $CSV_FILE
fi

echo "$TIMESTAMP,$WORKLOAD,$MNT_POINT,$BS,$FILE_SIZE,$RWMIX,$READ_BW,$READ_IOPS,$READ_LAT_US,$WRITE_BW,$WRITE_IOPS,$WRITE_LAT_US" >> $CSV_FILE
