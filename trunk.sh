#!/bin/bash

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

# ── Scan: collect repos that are NOT on their trunk branch ───────────────────

declare -a repos trunks branches

echo -e "${DIM}Scanning repositories...${RESET}"

while IFS= read -r line; do
  IFS=: read -r repo trunk skip <<< "$line"
  [[ -z "$repo" ]] && continue
  [[ "$skip" == "skip" ]] && continue
  [[ ! -d "$repo/.git" ]] && continue

  cd "$repo"
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || current_branch=""
  cd - > /dev/null

  [[ -z "$current_branch" ]] && continue

  if [[ "$current_branch" != "$trunk" ]]; then
    repos+=("$repo")
    trunks+=("$trunk")
    branches+=("$current_branch")
  fi
done < "$repo_file"

echo

if [[ ${#repos[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}✓${RESET}  ${BOLD_WHITE}All repositories are already on trunk.${RESET}"
  echo
  exit 0
fi

# ── Numbered selection table ──────────────────────────────────────────────────

count=${#repos[@]}

# Column widths
max_num=${#count}   # digits in the highest number (e.g. 2 for "10")
(( max_num < 1 )) && max_num=1
max_name=10         # min = header "Repository"
max_branch=6        # min = header "Branch"
max_trunk=5         # min = header "Trunk"

for (( i=0; i<count; i++ )); do
  name=$(basename "${repos[$i]}")
  branch="${branches[$i]}"
  trunk="${trunks[$i]}"
  (( ${#name}   > max_name   )) && max_name=${#name}
  (( ${#branch} > max_branch )) && max_branch=${#branch}
  (( ${#trunk}  > max_trunk  )) && max_trunk=${#trunk}
done

hr() { printf '─%.0s' $(seq 1 $(( $1 + 2 ))); }

echo -e "${BOLD}  Switch to trunk${RESET}"
echo

echo -e "  ┌$(hr $max_num)┬$(hr $max_name)┬$(hr $max_branch)┬$(hr $max_trunk)┐"
echo -e "  │ ${BOLD}$(pad_str "#" $max_num)${RESET} │ ${BOLD}$(pad_str "Repository" $max_name)${RESET} │ ${BOLD}$(pad_str "Branch" $max_branch)${RESET} │ ${BOLD}$(pad_str "Trunk" $max_trunk)${RESET} │"
echo -e "  ├$(hr $max_num)┼$(hr $max_name)┼$(hr $max_branch)┼$(hr $max_trunk)┤"

for (( i=0; i<count; i++ )); do
  num=$(( i + 1 ))
  name=$(basename "${repos[$i]}")
  branch="${branches[$i]}"
  trunk="${trunks[$i]}"

  num_p=$(pad_str    "$num"    $max_num)
  name_p=$(pad_str   "$name"   $max_name)
  branch_p=$(pad_str "$branch" $max_branch)
  trunk_p=$(pad_str  "$trunk"  $max_trunk)

  echo -e "  │ ${CYAN}${num_p}${RESET} │ ${BOLD_WHITE}${name_p}${RESET} │ ${YELLOW}${branch_p}${RESET} │ ${DIM}${trunk_p}${RESET} │"
done

echo -e "  └$(hr $max_num)┴$(hr $max_name)┴$(hr $max_branch)┴$(hr $max_trunk)┘"
echo

# ── Prompt ────────────────────────────────────────────────────────────────────

while true; do
  echo -e "${DIM}  Enter numbers separated by spaces, 'a' for all, or ENTER to cancel.${RESET}"
  printf "  ${BOLD_WHITE}>${RESET} "
  IFS= read -r input

  # Blank input → cancel
  if [[ -z "${input// }" ]]; then
    echo
    echo -e "  ${YELLOW}Cancelled.${RESET}"
    echo
    exit 0
  fi

  # 'a' or 'A' → select all
  if [[ "$input" == "a" || "$input" == "A" ]]; then
    input=""
    for (( i=1; i<=count; i++ )); do
      input+="$i "
    done
  fi

  # Parse and validate numbers
  declare -a selected_indices=()
  invalid=false

  for token in $input; do
    # Must be a positive integer
    if [[ ! "$token" =~ ^[0-9]+$ ]]; then
      echo -e "  ${RED}✗${RESET}  '${token}' is not a valid number."
      invalid=true
      break
    fi
    num=$token
    if (( num < 1 || num > count )); then
      echo -e "  ${RED}✗${RESET}  ${num} is out of range (1–${count})."
      invalid=true
      break
    fi
    # Convert to 0-based index, check for duplicates
    idx=$(( num - 1 ))
    already=false
    for existing in "${selected_indices[@]+"${selected_indices[@]}"}"; do
      [[ "$existing" == "$idx" ]] && already=true && break
    done
    [[ "$already" == "false" ]] && selected_indices+=("$idx")
  done

  $invalid && echo && continue

  if (( ${#selected_indices[@]} == 0 )); then
    echo -e "  ${YELLOW}No valid numbers entered.${RESET}"
    echo
    continue
  fi

  break
done

echo

# ── Execute git switch <trunk> on selected repos ──────────────────────────────

selected_count=${#selected_indices[@]}

if (( selected_count == 1 )); then
  echo -e "${DIM}  Switching 1 repository to trunk...${RESET}"
else
  echo -e "${DIM}  Switching ${selected_count} repositories to trunk...${RESET}"
fi
echo

declare -a col_repo col_from col_trunk_col col_result col_type
max_repo=10
max_from=4      # min = header "From"
max_trunk_col=5 # min = header "Trunk"
max_result=6    # min = header "Result"

for idx in "${selected_indices[@]}"; do
  repo="${repos[$idx]}"
  trunk="${trunks[$idx]}"
  branch="${branches[$idx]}"
  name=$(basename "$repo")

  printf "  ${DIM}→  %s  switching...${RESET}" "$name"

  cd "$repo"

  # Stash uncommitted changes so the switch doesn't fail
  did_stash=false
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    if git stash -m "Auto-stash: $(date +"%Y-%m-%d %H:%M:%S")" --quiet 2>/dev/null; then
      did_stash=true
    fi
  fi

  if git switch "$trunk" --quiet 2>/dev/null; then
    row_result="switched"
    row_type="ok"
    printf "\r\033[K  ${GREEN}✓${RESET}  %s  ${DIM}(%s → %s)${RESET}  ${GREEN}switched${RESET}\n" "$name" "$branch" "$trunk"
  else
    row_result="error"
    row_type="error"
    [[ "$did_stash" == "true" ]] && git stash pop --quiet 2>/dev/null || true
    printf "\r\033[K  ${RED}✗${RESET}  %s  ${DIM}(%s → %s)${RESET}  ${RED}error${RESET}\n" "$name" "$branch" "$trunk"
  fi

  cd - > /dev/null

  col_repo+=("$name")
  col_from+=("$branch")
  col_trunk_col+=("$trunk")
  col_result+=("$row_result")
  col_type+=("$row_type")

  (( ${#name}       > max_repo      )) && max_repo=${#name}
  (( ${#branch}     > max_from      )) && max_from=${#branch}
  (( ${#trunk}      > max_trunk_col )) && max_trunk_col=${#trunk}
  (( ${#row_result} > max_result    )) && max_result=${#row_result}
done

echo

# ── Summary table ─────────────────────────────────────────────────────────────

echo
echo -e "  ┌$(hr $max_repo)┬$(hr $max_from)┬$(hr $max_trunk_col)┬$(hr $max_result)┐"
echo -e "  │ ${BOLD}$(pad_str "Repository" $max_repo)${RESET} │ ${BOLD}$(pad_str "From" $max_from)${RESET} │ ${BOLD}$(pad_str "Trunk" $max_trunk_col)${RESET} │ ${BOLD}$(pad_str "Result" $max_result)${RESET} │"
echo -e "  ├$(hr $max_repo)┼$(hr $max_from)┼$(hr $max_trunk_col)┼$(hr $max_result)┤"

for i in "${!col_repo[@]}"; do
  repo_v="${col_repo[$i]}"
  from_v="${col_from[$i]}"
  trunk_v="${col_trunk_col[$i]}"
  result_v="${col_result[$i]}"
  type_v="${col_type[$i]}"

  repo_p=$(pad_str   "$repo_v"   $max_repo)
  from_p=$(pad_str   "$from_v"   $max_from)
  trunk_p=$(pad_str  "$trunk_v"  $max_trunk_col)
  result_p=$(pad_str "$result_v" $max_result)

  case "$type_v" in
    ok)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${from_p}${RESET} │ ${GREEN}${trunk_p}${RESET} │ ${GREEN}${result_p}${RESET} │"
      ;;
    error)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${CYAN}${from_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${RED}${result_p}${RESET} │"
      ;;
    *)
      echo -e "  │ ${DIM}${repo_p}${RESET} │ ${DIM}${from_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${YELLOW}${result_p}${RESET} │"
      ;;
  esac
done

echo -e "  └$(hr $max_repo)┴$(hr $max_from)┴$(hr $max_trunk_col)┴$(hr $max_result)┘"
echo
echo -e "${BOLD_WHITE}All done!${RESET}"
