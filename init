#!/bin/bash

set -euo pipefail

path=$1
repo_file=$2

[[ ! -d repos ]] && mkdir -p repos

> "$repo_file"  # Clear/create the file

echo "Writing to $repo_file"

for dir in "$path"/*/; do
  if [[ -d "$dir/.git" ]]; then
    cd "$dir"
    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "$PWD:$branch:" >> "$repo_file"
    echo "Wrote $PWD:$branch"
    cd - > /dev/null
  fi
done

echo -e "\033[1;37mAll done!\033[0m"

