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
SIFTR2_PATH="/root/siftr2"  # Module location

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

script=/root/research_scripts/fbsd_snd_nosiftr.bash

for i in {1..4}; do
    folder="${name}.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in ${folder}..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo ""
    sleep 10
done

script=/root/research_scripts/fbsd_snd.bash
for i in {1..1}; do
    folder="${name}.siftr.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in $folder..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo ""
done

kldunload siftr2
