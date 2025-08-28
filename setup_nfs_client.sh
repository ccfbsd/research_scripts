#!/bin/sh
# Flexible NFS client setup on FreeBSD/Linux
# Usage: ./setup_nfs_client.sh SERVER_IP [EXPORT_DIR] [MOUNT_DIR]

SERVER=${1}
EXPORT_DIR=${2:-/mnt/nfs_mem}
MOUNT_DIR=${3:-/mnt/nfs}

if [ -z "${SERVER}" ]; then
    echo "Usage: $0 SERVER_IP [EXPORT_DIR] [MOUNT_DIR]"
    exit 1
fi

echo ">>> Setting up NFS client for server ${SERVER}, export ${EXPORT_DIR}"

# Create mount dir if missing
mkdir -p "${MOUNT_DIR}"

# Try NFSv4 first
echo ">>> Trying NFSv4..."
if mount -t nfs -o vers=4,proto=tcp "${SERVER}:${EXPORT_DIR}" "${MOUNT_DIR}" 2>/dev/null; then
    echo ">>> Mounted NFSv4 successfully."
else
    echo ">>> NFSv4 failed, falling back to NFSv3..."
    if mount -t nfs -o vers=3,proto=tcp "${SERVER}:${EXPORT_DIR}" "${MOUNT_DIR}"; then
        echo ">>> Mounted NFSv3 successfully."
    else
        echo "!!! Failed to mount NFS share from ${SERVER}"
        exit 1
    fi
fi

echo ">>> Mounted NFS share from ${SERVER}:${EXPORT_DIR} at ${MOUNT_DIR}"
df -h "${MOUNT_DIR}"

# --- Verification step ---
echo ">>> Verifying mount details..."
if command -v nfsstat >/dev/null 2>&1; then
    nfsstat -m | grep -A 1 "${MOUNT_DIR}"
else
    # Fallback: use mount output
    mount | grep "${MOUNT_DIR}"
fi

df -h "${MOUNT_DIR}"