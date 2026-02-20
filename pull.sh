#!/bin/bash

set -euo pipefail

# If the local branch is a direct ancestor of the remote branch,
# Git will simply move the local branch pointer forward to the latest commit on the remote branch.
# This results in no new merge commit being created, and the history remains linear.
git config --global pull.ff true

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
			current_branch="$(git rev-parse --abbrev-ref HEAD)"
			# Stash any uncommitted changes before pulling, this is reapplied once the process is complete.
			git stash -m "Auto-stash: $(date +"%Y-%m-%d %H:%M:%S")"
			if [[ $current_branch != $trunk ]]; then
				# Always update the current branch but without a rebase because it will break for other collaborators.
				# Update trunk branch with a rebase to ensure the history is linear and clean and we are not accidentally creating a merge commit.
				# Switch back to current branch for convenience.
				echo -e "\033[1;mUpdating $current_branch ...\033[0m"
				git pull origin "$trunk"
				echo -e "\033[1;mUpdating $trunk ...\033[0m"
				git switch $trunk
				git pull --rebase origin "$trunk"
				git switch $current_branch
			else
			  # No need for all the branching fluff, simply update trunk without an accidental merge commit.
			  echo -e "\033[1;mUpdating $trunk ...\033[0m\033[0m"
				git pull --rebase origin "$trunk"
			fi

			if git stash list | grep -q .; then
				if ! git stash pop -q; then
					echo -e "\033[31mStash pop had conflicts; continuing\033[0m"
				fi
			fi
			cd - > /dev/null
		fi
		echo
	fi
done < "$repo_file"

echo -e "\033[1;37mAll done!\033[0m"
