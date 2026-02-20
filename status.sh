#!/bin/bash

set -euo pipefail

# In the root of your lifecheq directory, create a repos.txt file with the format:
# <repo>:<trunk_branch>:<skip>
# Example:
# repo:main:skip
# Only add skip if you want to skip the repo, otherwise leave it blank. The trunk branch is the branch that all other branches are based on, and is typically the main or master branch.

path=$1
repo_file=$2

while IFS= read -r line; do
  IFS=: read -r repo trunk skip <<< "$line"

	if [[ "$skip" == "skip" ]]; then
		echo -e "\033[33mSkipping $repo ($trunk)\033[0m"
		continue
	else
		echo -e "\033[32m$repo ($trunk)\033[0m"
		if [[ ! -z "$repo" ]]; then
			cd "$repo"
			git status
			echo
			cd - > /dev/null
		fi
	fi
done < "$repo_file"

echo -e "\033[1;37mAll done!\033[0m"

