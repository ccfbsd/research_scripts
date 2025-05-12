#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

script=/root/research_scripts/linux_snd_notrace.bash

for i in {1..3}; do
    folder="${name}.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in ${folder}..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo "" && sleep 10
done

script=/root/research_scripts/linux_snd.bash
for i in {1..1}; do
    folder="${name}.trace.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in $folder..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo ""
done