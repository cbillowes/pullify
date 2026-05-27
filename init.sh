#!/bin/bash

set -euo pipefail

path=$1
repo_file=$2

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
CYAN="\033[36m"
BOLD_WHITE="\033[1;37m"

# Pad $1 to visual width $2, compensating for multi-byte Unicode characters.
pad_str() {
  local str="$1" width="$2"
  local byte_len=${#str}
  local char_len
  char_len=$(printf '%s' "$str" | wc -m | tr -d '[:space:]')
  printf "%-$(( width + byte_len - char_len ))s" "$str"
}

[[ ! -d repos ]] && mkdir -p repos

> "$repo_file"  # Clear/create the file

# ── First pass: collect rows and compute column widths ────────────────────────

declare -a col_repo col_branch

max_repo=10     # min width = header "Repository"
max_branch=6    # min width = header "Branch"

echo -e "${DIM}Scanning $path...${RESET}" >&2
echo -e "${DIM}Writing to $repo_file${RESET}" >&2
echo >&2

for dir in "$path"/*/; do
  if [[ -d "$dir/.git" ]]; then
    cd "$dir"
    branch=$(git rev-parse --abbrev-ref HEAD)
    repo=$(basename "$PWD")

    echo "$PWD:$branch:" >> "$repo_file"
    printf "  ${GREEN}✓${RESET}  %s  ${DIM}(%s)${RESET}\n" "$repo" "$branch" >&2

    col_repo+=("$repo")
    col_branch+=("$branch")

    (( ${#repo}   > max_repo   )) && max_repo=${#repo}
    (( ${#branch} > max_branch )) && max_branch=${#branch}

    cd - > /dev/null
  fi
done

echo >&2

# ── Second pass: render table ─────────────────────────────────────────────────

hr() { printf '─%.0s' $(seq 1 $(( $1 + 2 ))); }

echo
echo -e "  ┌$(hr $max_repo)┬$(hr $max_branch)┐"
echo -e "  │ ${BOLD}$(pad_str "Repository" $max_repo)${RESET} │ ${BOLD}$(pad_str "Branch" $max_branch)${RESET} │"
echo -e "  ├$(hr $max_repo)┼$(hr $max_branch)┤"

for i in "${!col_repo[@]}"; do
  repo_p=$(pad_str   "${col_repo[$i]}"   $max_repo)
  branch_p=$(pad_str "${col_branch[$i]}" $max_branch)
  echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${CYAN}${branch_p}${RESET} │"
done

echo -e "  └$(hr $max_repo)┴$(hr $max_branch)┘"
echo
echo -e "  ${DIM}Written to ${repo_file}${RESET}"
echo
echo -e "${BOLD_WHITE}All done!${RESET}"
