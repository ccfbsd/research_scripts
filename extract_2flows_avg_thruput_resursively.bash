#!/bin/bash

tcp_fairness() {
    local x1=$1
    local x2=$2

    if [[ -z "$x1" || -z "$x2" ]]; then
        echo "Usage: tcp_fairness <throughput1> <throughput2>" >&2
        return 1
    fi

    awk -v a="$x1" -v b="$x2" 'BEGIN {
        sum = a + b;
        fairness = (sum * sum) / (2 * (a * a + b * b));
        printf "%.1f\n", fairness * 100;
    }'
}

extract_goodput_info() {
    local base_dir="${1:-.}"  # Default to current directory if not given
    local csv_file=$2
    local table_file=$3

    # Check if the directory has no subdirectories
    if ! find "${dir}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        local thruput_logs=(${dir}/*.avg.goodput)
        # Check if exactly two matching iperf3 logs exist
        if [ ${#thruput_logs[@]} -ne 2 ] || [ ! -e "${thruput_logs[0]}" ] || \
           [ ! -e "${thruput_logs[1]}" ]; then
            echo "Skipping ${dir}: required average throughput logs not found"
            return
        fi

        local parent_folder grandparent_folder f1_avg_thruput f2_avg_thruput
        parent_folder=$(basename "${dir}")
        grandparent_folder=$(basename "$(dirname "${dir}")")
        f1_avg_thruput=$(printf "%g\n" $(<"${thruput_logs[0]}"))
        f2_avg_thruput=$(printf "%g\n" $(<"${thruput_logs[1]}"))
        sum=$(echo "${f1_avg_thruput} + ${f2_avg_thruput}" | bc)
        local fairness_pct=$(tcp_fairness ${f1_avg_thruput} ${f2_avg_thruput})
        
        # Append to CSV
        printf "%s,%s,%s,%s,%s,%s\n" \
               "${grandparent_folder}" "${parent_folder}" "${f1_avg_thruput}" \
               "${f2_avg_thruput}" "${sum}" "${fairness_pct}%" >> "${csv_file}"

        # Append to wiki table
        printf "|| %s || %s || %s || %s || %s || %s ||\n" \
               "${grandparent_folder}" "${parent_folder}" "${f1_avg_thruput}" \
               "${f2_avg_thruput}" "${sum}" "${fairness_pct}%" >> "${table_file}"
    fi
}

# Starting point (default to current directory if not given)
root_dir="${1:-.}"

# Create CSV with one row and a header
csv_file="$(pwd)/output.csv"
echo "version,TCP CC,flow1 avg thruput,flow2 avg thruput,sum(flow1 + flow2),TCP fairness" \
     > "${csv_file}"

sorted_csv_file="$(pwd)/$(basename $(pwd))_sorted_output.csv"

# Create a stats table in MoinMoin wiki format
wiki_table_file="$(pwd)/$(basename $(pwd))_wiki_table.txt"
echo "|| version || TCP CC || flow1 avg thruput || flow2 avg thruput|| link utilization = sum(flow1+flow2) || TCP fairness ||" \
     > "${wiki_table_file}"

# Find all directories and apply the function
find "$root_dir" -type d | while read -r dir; do
    echo -e "under ${dir}:"
    extract_goodput_info "$dir" "${csv_file}" "${wiki_table_file}"
    (head -n 1 "${csv_file}" && tail -n +2 "${csv_file}" | sort -t',' -k2) > \
    "${sorted_csv_file}"
done

rm ${csv_file}

# open in Numbers
open -a "Numbers" "${sorted_csv_file}"
