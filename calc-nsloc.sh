#!/bin/bash

# Function to calculate nSLOC in a single Solidity file
calculate_nsloc() {
    file=$1
    grep -Ev '^\s*(//|/\*|\*/|\*)|^\s*$' "$file" | wc -l
}

# Loop through all Solidity files in the 'src' directory
total_nsloc=0
for file in $(find src -name '*.sol'); do
    nsloc=$(calculate_nsloc "$file")
    echo "$file: $nsloc"
    total_nsloc=$((total_nsloc + nsloc))
done

echo "Total nSLOC: $total_nsloc"