#!/bin/sh
# Flexible NFS client setup on FreeBSD
# Usage: ./setup_nfs_client.sh SERVER_IP EXPORT_DIR MOUNT_DIR

SERVER=${1}
EXPORT_DIR=${2:-/mnt/nfs_mem}
MOUNT_DIR=${3:-/mnt/nfs}

if [ -z "${SERVER}" ]; then
    echo "Usage: $0 SERVER_IP EXPORT_DIR [MOUNT_DIR]"
    exit 1
fi

echo ">>> Setting up NFS client for server ${SERVER}, export ${EXPORT_DIR}"

# Create mount dir if missing
mkdir -p ${MOUNT_DIR}

# Try NFSv4 first
echo ">>> Trying NFSv4..."
mount -t nfs -o nfsv4,tcp ${SERVER}:${EXPORT_DIR} ${MOUNT_DIR} 2>/tmp/nfsmount.err
if [ $? -ne 0 ]; then
    echo "NFSv4 failed, falling back to NFSv3..."
    mount -t nfs -o tcp ${SERVER}:${EXPORT_DIR} ${MOUNT_DIR}
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to mount NFS export from ${SERVER}"
        cat /tmp/nfsmount.err
        exit 1
    fi
fi

echo ">>> Mounted NFS share from ${SERVER}:${EXPORT_DIR} at ${MOUNT_DIR}"
df -h ${MOUNT_DIR}