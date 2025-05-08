#!/bin/bash

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

script=/root/research_scripts/fbsd_snd_nosiftr.bash

for i in {1..3}; do
    folder="${name}.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in ${folder}..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo ""
done

script=/root/research_scripts/fbsd_snd.bash
for i in {1..3}; do
    folder="${name}.siftr.$i"
    mkdir -p "${folder}"
    cd "${folder}" || exit 1

    echo "Running ${script} in $folder..."
    bash ${script} ${name} ${src} ${dst} ${seconds}

    cd ..
    echo ""
done
