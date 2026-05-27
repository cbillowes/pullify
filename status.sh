#!/bin/bash

set -euo pipefail

# In the root of your lifecheq directory, create a repos.txt file with the format:
# <repo>:<trunk_branch>:<skip>
# Example:
# repo:main:skip
# Only add skip if you want to skip the repo, otherwise leave it blank. The trunk branch is the branch
# that all other branches are based on, and is typically the main or master branch.

path=$1
repo_file=$2

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
BOLD_WHITE="\033[1;37m"

# Pad $1 to visual width $2, compensating for multi-byte Unicode characters.
# printf "%-Ns" counts bytes, not visible columns — e.g. "✓" is 3 bytes but 1
# column, so without correction the cell comes out 2 columns too narrow.
pad_str() {
  local str="$1" width="$2"
  local byte_len=${#str}
  local char_len
  char_len=$(printf '%s' "$str" | wc -m | tr -d '[:space:]')
  printf "%-$(( width + byte_len - char_len ))s" "$str"
}

# ── First pass: collect rows and compute column widths ────────────────────────

declare -a col_repo col_trunk col_branch col_status col_type

max_repo=10     # min width = header "Repository"
max_trunk=5     # min width = header "Trunk"
max_branch=6    # min width = header "Branch"
max_status=6    # min width = header "Status"

echo -e "${DIM}Scanning repositories...${RESET}" >&2
echo >&2

while IFS= read -r line; do
  IFS=: read -r repo trunk skip <<< "$line"
  [[ -z "$repo" ]] && continue

  col_repo+=("$repo")
  col_trunk+=("$trunk")

  # Capture branch and status into locals first so we can track widths
  # without using [-1] array subscript (not supported in bash < 4.2)
  if [[ "$skip" == "skip" ]]; then
    row_branch="-"
    row_status="skipped"
    row_type="skip"
    printf "  ${YELLOW}⊘${RESET}  %s  ${DIM}(%s)${RESET}  ${YELLOW}skipped${RESET}\n" "$repo" "$trunk" >&2
  else
    cd "$repo"
    current_branch="$(git rev-parse --abbrev-ref HEAD)"

    # Show a "fetching" placeholder; \r + \033[K overwrites it with the result
    printf "  ${DIM}→  %s  fetching...${RESET}" "$repo" >&2

    # Always fetch trunk; also fetch the feature branch if we're not on trunk
    git fetch origin "$trunk" --quiet 2>/dev/null || true
    if [[ "$current_branch" != "$trunk" ]]; then
      git fetch origin "$current_branch" --quiet 2>/dev/null || true
    fi

    # How many commits in origin/trunk are not yet in the current branch?
    behind_trunk=$(git rev-list --count "HEAD..origin/${trunk}" 2>/dev/null || echo "?")

    # How many commits in origin/<current_branch> are not yet local?
    # Only relevant on a feature branch that has a remote counterpart.
    if [[ "$current_branch" != "$trunk" ]] && git rev-parse --verify "origin/${current_branch}" >/dev/null 2>&1; then
      behind_branch=$(git rev-list --count "HEAD..origin/${current_branch}" 2>/dev/null || echo "?")
    else
      behind_branch="0"
    fi

    row_branch="$current_branch"

    # Build status parts list, then join with " · "
    status_parts=()
    [[ "$behind_trunk"  != "0" && "$behind_trunk"  != "?" ]] && status_parts+=("${behind_trunk} behind trunk")
    [[ "$behind_branch" != "0" && "$behind_branch" != "?" ]] && status_parts+=("${behind_branch} behind origin")

    if [[ "$behind_trunk" == "?" || "$behind_branch" == "?" ]]; then
      row_status="unknown"
      row_type="unknown"
    elif [[ ${#status_parts[@]} -eq 0 ]]; then
      row_status="up to date"
      row_type="ok"
    else
      row_status="${status_parts[0]}"
      [[ ${#status_parts[@]} -gt 1 ]] && row_status="${status_parts[0]} · ${status_parts[1]}"
      row_type="behind"
    fi

    # Verbose result line (overwrites the placeholder)
    if [[ "$current_branch" == "$trunk" ]]; then
      branch_ctx="${DIM}(${trunk})${RESET}"
    else
      branch_ctx="${DIM}(${trunk} → ${current_branch})${RESET}"
    fi
    case "$row_type" in
      ok)      printf "\r\033[K  ${GREEN}✓${RESET}  %s  ${branch_ctx}  ${GREEN}%s${RESET}\n"  "$repo" "$row_status" >&2 ;;
      behind)  printf "\r\033[K  ${RED}✗${RESET}  %s  ${branch_ctx}  ${RED}%s${RESET}\n"    "$repo" "$row_status" >&2 ;;
      *)       printf "\r\033[K  ${YELLOW}?${RESET}  %s  ${branch_ctx}  ${YELLOW}%s${RESET}\n" "$repo" "$row_status" >&2 ;;
    esac

    cd - > /dev/null
  fi

  col_branch+=("$row_branch")
  col_status+=("$row_status")
  col_type+=("$row_type")

  # Track max plain-text widths for alignment
  (( ${#repo}       > max_repo   )) && max_repo=${#repo}
  (( ${#trunk}      > max_trunk  )) && max_trunk=${#trunk}
  (( ${#row_branch} > max_branch )) && max_branch=${#row_branch}
  (( ${#row_status} > max_status )) && max_status=${#row_status}

done < "$repo_file"

echo >&2

# ── Second pass: render table ─────────────────────────────────────────────────

# +2 for the icon + space prefix on the status column
status_col_width=$(( max_status + 2 ))

# Horizontal rule segments (─ repeated to fill each column including its padding)
hr() { printf '─%.0s' $(seq 1 $(( $1 + 2 ))); }

echo
echo -e "  ┌$(hr $max_repo)┬$(hr $max_trunk)┬$(hr $max_branch)┬$(hr $status_col_width)┐"
echo -e "  │ ${BOLD}$(pad_str "Repository" $max_repo)${RESET} │ ${BOLD}$(pad_str "Trunk" $max_trunk)${RESET} │ ${BOLD}$(pad_str "Branch" $max_branch)${RESET} │ ${BOLD}$(pad_str "  Status" $status_col_width)${RESET} │"
echo -e "  ├$(hr $max_repo)┼$(hr $max_trunk)┼$(hr $max_branch)┼$(hr $status_col_width)┤"

for i in "${!col_repo[@]}"; do
  repo="${col_repo[$i]}"
  trunk="${col_trunk[$i]}"
  branch="${col_branch[$i]}"
  status="${col_status[$i]}"
  type="${col_type[$i]}"

  # Pre-pad strings to their column's visual width before applying color.
  # pad_str compensates for multi-byte Unicode so printf byte-counting doesn't
  # produce columns that are visually too narrow.
  repo_p=$(pad_str   "$repo"   $max_repo)
  trunk_p=$(pad_str  "$trunk"  $max_trunk)
  branch_p=$(pad_str "$branch" $max_branch)
  status_p=$(pad_str "$status" $max_status)

  case "$type" in
    ok)
      icon="${GREEN}✓${RESET}"
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${CYAN}${branch_p}${RESET} │ ${icon} ${GREEN}${status_p}${RESET} │"
      ;;
    behind)
      icon="${RED}✗${RESET}"
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${CYAN}${branch_p}${RESET} │ ${icon} ${RED}${status_p}${RESET} │"
      ;;
    skip)
      icon="${YELLOW}⊘${RESET}"
      echo -e "  │ ${DIM}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${DIM}${branch_p}${RESET} │ ${icon} ${YELLOW}${status_p}${RESET} │"
      ;;
    *)
      icon="${YELLOW}?${RESET}"
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${DIM}${branch_p}${RESET} │ ${icon} ${YELLOW}${status_p}${RESET} │"
      ;;
  esac
done

echo -e "  └$(hr $max_repo)┴$(hr $max_trunk)┴$(hr $max_branch)┴$(hr $status_col_width)┘"
echo
echo -e "${BOLD_WHITE}All done!${RESET}"
