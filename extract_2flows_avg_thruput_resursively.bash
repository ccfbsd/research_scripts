#!/bin/bash

extract_goodput_info() {
    local base_dir="${1:-.}"  # Default to current directory if not given
    local csv_file=$2

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
        
        # Append to CSV
        printf "%s,%s,%s,%s,%s\n" \
               "${grandparent_folder}" "${parent_folder}" "${f1_avg_thruput}" \
               "${f2_avg_thruput}" "${sum}" >> "${csv_file}"
    fi
}

# Starting point (default to current directory if not given)
root_dir="${1:-.}"

# Create CSV with one row and a header
csv_file="$(pwd)/output.csv"
echo "version,TCP CC,flow1 avg thruput,flow2 avg thruput,sum(flow1 + flow2)" \
     > "${csv_file}"

sorted_csv_file="$(pwd)/sorted_output.csv"

# Find all directories and apply the function
find "$root_dir" -type d | while read -r dir; do
    echo -e "under ${dir}:"
    extract_goodput_info "$dir" "${csv_file}"
    (head -n 1 "${csv_file}" && tail -n +2 "${csv_file}" | sort -t',' -k2) > \
    "${sorted_csv_file}"
done

rm ${csv_file}

# open in Numbers
open -a "Numbers" "${sorted_csv_file}"
