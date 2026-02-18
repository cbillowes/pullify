#!/bin/bash

set -euo pipefail

path=$1

echo "Scanning directory $path"

for dir in "$path"/*/; do
  if [[ -d "$dir/.git" ]]; then
    cd "$dir"
    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "$(basename "$PWD"): $branch"
    cd - > /dev/null
  fi
done

echo -e "\033[1;37mAll done!\033[0m"

