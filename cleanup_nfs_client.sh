#!/bin/sh
# Usage: ./cleanup_nfs_client.sh MOUNT_DIR
MOUNT_DIR=${1:-/mnt/nfs}

echo ">>> Unmounting ${MOUNT_DIR}..."
umount -f ${MOUNT_DIR} 2>/dev/null

if [ $? -eq 0 ]; then
    echo ">>> Successfully unmounted ${MOUNT_DIR}"
else
    echo ">>> WARNING: Failed to unmount ${MOUNT_DIR} (maybe not mounted)"
fi

# Optional cleanup
if [ -d ${MOUNT_DIR} ]; then
    rmdir ${MOUNT_DIR} 2>/dev/null
fi