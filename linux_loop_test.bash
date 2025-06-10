#!/bin/bash

if [  $# -ne 4 ]; then
    echo -e "\nUsage:\n$0 <name> <src> <dst> <seconds>\n example: bash $0 cubic s1 r1 10\n"
    exit 1
fi

name=$1              # TCP congestion control name
src=$2
dst=$3
seconds=$4

interval=$(echo "${seconds} + 10" | bc | awk '{printf "%d\n", $1}')
start_time=$(date +%s)
next_time=$(( start_time + interval ))
echo "start_time: [$start_time], interval: [$interval]"

script=/root/research_scripts/linux_snd_notrace.bash
for i in {1..5}; do
    folder="${name}.$i"
    mkdir -p ${folder}
    cd ${folder} || exit 1

    echo "[$(date +%s)] Running ${script} in ${folder}..."
    bash ${script} ${name} ${src} ${dst} ${seconds}
    finish_time=$(date +%s)
    echo "script running finished at: [${finish_time}]"
    cd ..
    echo -e "next run is scheduled at: [${next_time}], delta: [$(( next_time - finish_time ))]\n"

    while true; do
        now=$(date +%s)
        if [ "$now" -lt "$next_time" ]; then
            sleep 0.1
        else
            next_time=$(( next_time + interval ))
            break
        fi
    done
done

script=/root/research_scripts/linux_snd.bash
for i in {6..6}; do
    folder="${name}.trace.$i"
    mkdir -p ${folder}
    cd ${folder} || exit 1

    echo "[$(date +%s)] Running ${script} in ${folder}..."
    bash ${script} ${name} ${src} ${dst} ${seconds}
    finish_time=$(date +%s)
    echo "script running finished at: [${finish_time}]"
    cd ..
    echo -e "next run is scheduled at: [${next_time}], delta: [$(( next_time - finish_time ))]\n"

    while true; do
        now=$(date +%s)
        if [ "$now" -lt "$next_time" ]; then
            sleep 0.1
        else
            next_time=$(( next_time + interval ))
            break
        fi
    done
done
