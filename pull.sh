#!/bin/bash

set -euo pipefail

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

# ── Collect results and pull where needed ─────────────────────────────────────

declare -a col_repo col_trunk col_branch col_trunk_pulled col_branch_updated col_stash col_result col_type

max_repo=10     # min = "Repository"
max_trunk=5     # min = "Trunk"
max_branch=6    # min = "Branch"
max_stash=8     # min = "conflict"
max_result=10   # min = "up to date"

# Indicator columns are fixed-width: header drives the minimum
max_trunk_pulled=7    # "Trunk ↓"
max_branch_updated=8  # "Branch ↓"

echo -e "${DIM}Checking repositories...${RESET}" >&2
echo >&2

while IFS= read -r line; do
  IFS=: read -r repo trunk skip <<< "$line"
  [[ -z "$repo" ]] && continue

  col_repo+=("$repo")
  col_trunk+=("$trunk")

  if [[ "$skip" == "skip" ]]; then
    row_branch="-"
    row_trunk_pulled="–"
    row_branch_updated="–"
    row_stash="–"
    row_result="skipped"
    row_type="skip"
    printf "  ${YELLOW}⊘${RESET}  %s  ${DIM}(%s)${RESET}  ${YELLOW}skipped${RESET}\n" "$repo" "$trunk" >&2
  else
    cd "$repo"
    current_branch="$(git rev-parse --abbrev-ref HEAD)"

    printf "  ${DIM}→  %s  fetching...${RESET}" "$repo" >&2

    # Fetch trunk and, when on a feature branch, its remote counterpart
    git fetch origin "$trunk" --quiet 2>/dev/null || true
    if [[ "$current_branch" != "$trunk" ]]; then
      git fetch origin "$current_branch" --quiet 2>/dev/null || true
    fi

    # Is the LOCAL trunk branch itself behind origin/trunk?
    if [[ "$current_branch" == "$trunk" ]]; then
      behind_local_trunk=$(git rev-list --count "HEAD..origin/${trunk}" 2>/dev/null || echo "?")
    else
      behind_local_trunk=$(git rev-list --count "${trunk}..origin/${trunk}" 2>/dev/null || echo "?")
    fi

    # Does the current branch (feature or trunk) still need commits from origin/trunk?
    behind_trunk=$(git rev-list --count "HEAD..origin/${trunk}" 2>/dev/null || echo "?")

    # Is the feature branch behind its own remote?
    if [[ "$current_branch" != "$trunk" ]] && git rev-parse --verify "origin/${current_branch}" >/dev/null 2>&1; then
      behind_branch=$(git rev-list --count "HEAD..origin/${current_branch}" 2>/dev/null || echo "?")
    else
      behind_branch="0"
    fi

    row_branch="$current_branch"
    row_trunk_pulled="–"
    row_branch_updated="–"
    row_stash="–"

    needs_trunk_update=false
    needs_branch_update=false
    [[ "$behind_local_trunk" != "0" && "$behind_local_trunk" != "?" ]] && needs_trunk_update=true
    [[ "$behind_trunk"       != "0" && "$behind_trunk"       != "?" ]] && needs_branch_update=true
    [[ "$behind_branch"      != "0" && "$behind_branch"      != "?" ]] && needs_branch_update=true

    if [[ "$current_branch" == "$trunk" ]]; then
      branch_ctx="${DIM}(${trunk})${RESET}"
    else
      branch_ctx="${DIM}(${trunk} → ${current_branch})${RESET}"
    fi

    if ! $needs_trunk_update && ! $needs_branch_update; then
      # ── Nothing to do ──────────────────────────────────────────────────────
      row_result="up to date"
      row_type="ok"
      printf "\r\033[K  ${GREEN}✓${RESET}  %s  ${branch_ctx}  ${GREEN}up to date${RESET}\n" "$repo" >&2
    else
      # ── Pull required ──────────────────────────────────────────────────────
      printf "\r\033[K  ${CYAN}↓${RESET}  %s  ${branch_ctx}  ${CYAN}updating...${RESET}" "$repo" >&2

      # Stash uncommitted changes (only if there are any)
      did_stash=false
      if [[ -n "$(git status --porcelain)" ]]; then
        git stash -m "Auto-stash: $(date +"%Y-%m-%d %H:%M:%S")" --quiet
        did_stash=true
      fi

      update_error=false

      if [[ "$current_branch" == "$trunk" ]]; then
        # On trunk — pull trunk with rebase to keep history linear
        if $needs_trunk_update; then
          if git -c pull.ff=true pull --rebase origin "$trunk" --quiet 2>/dev/null; then
            row_trunk_pulled="✓"
          else
            git rebase --abort 2>/dev/null || true
            row_trunk_pulled="✗"
            update_error=true
          fi
        fi
      else
        # On a feature branch — three independent updates:

        # 1. Merge origin/trunk into feature branch if it's behind trunk
        if [[ "$behind_trunk" != "0" && "$behind_trunk" != "?" ]]; then
          if git -c pull.ff=true pull origin "$trunk" --quiet 2>/dev/null; then
            row_branch_updated="✓"
          else
            git merge --abort 2>/dev/null || true
            row_branch_updated="✗"
            update_error=true
          fi
        fi

        # 2. Pull any remote-only commits on the feature branch itself
        if [[ "$behind_branch" != "0" && "$behind_branch" != "?" ]]; then
          if git -c pull.ff=true pull origin "$current_branch" --quiet 2>/dev/null; then
            row_branch_updated="✓"
          else
            git merge --abort 2>/dev/null || true
            row_branch_updated="✗"
            update_error=true
          fi
        fi

        # 3. Update local trunk via rebase (switch away, pull, switch back)
        if $needs_trunk_update; then
          if git switch "$trunk" --quiet 2>/dev/null &&
             git -c pull.ff=true pull --rebase origin "$trunk" --quiet 2>/dev/null; then
            row_trunk_pulled="✓"
          else
            git rebase --abort 2>/dev/null || true
            row_trunk_pulled="✗"
            update_error=true
          fi
          git switch "$current_branch" --quiet 2>/dev/null || true
        fi
      fi

      # Restore stashed changes
      if $did_stash; then
        if git stash pop --quiet 2>/dev/null; then
          row_stash="restored"
        else
          row_stash="conflict"
        fi
      fi

      if $update_error; then
        row_result="error"
        row_type="error"
        printf "\r\033[K  ${RED}✗${RESET}  %s  ${branch_ctx}  ${RED}error${RESET}\n" "$repo" >&2
      else
        row_result="updated"
        row_type="updated"
        printf "\r\033[K  ${GREEN}↓${RESET}  %s  ${branch_ctx}  ${GREEN}updated${RESET}\n" "$repo" >&2
      fi
    fi

    cd - > /dev/null
  fi

  col_branch+=("$row_branch")
  col_trunk_pulled+=("$row_trunk_pulled")
  col_branch_updated+=("$row_branch_updated")
  col_stash+=("$row_stash")
  col_result+=("$row_result")
  col_type+=("$row_type")

  (( ${#repo}       > max_repo   )) && max_repo=${#repo}
  (( ${#trunk}      > max_trunk  )) && max_trunk=${#trunk}
  (( ${#row_branch} > max_branch )) && max_branch=${#row_branch}
  (( ${#row_stash}  > max_stash  )) && max_stash=${#row_stash}
  (( ${#row_result} > max_result )) && max_result=${#row_result}

done < "$repo_file"

echo >&2

# ── Summary table ─────────────────────────────────────────────────────────────

hr() { printf '─%.0s' $(seq 1 $(( $1 + 2 ))); }

echo
echo -e "  ┌$(hr $max_repo)┬$(hr $max_trunk)┬$(hr $max_branch)┬$(hr $max_trunk_pulled)┬$(hr $max_branch_updated)┬$(hr $max_stash)┬$(hr $max_result)┐"
echo -e "  │ ${BOLD}$(printf "%-${max_repo}s"            "Repository")${RESET} │ ${BOLD}$(printf "%-${max_trunk}s"           "Trunk")${RESET} │ ${BOLD}$(printf "%-${max_branch}s"          "Branch")${RESET} │ ${BOLD}$(printf "%-${max_trunk_pulled}s"    "Trunk ↓")${RESET} │ ${BOLD}$(printf "%-${max_branch_updated}s"  "Branch ↓")${RESET} │ ${BOLD}$(printf "%-${max_stash}s"            "Stash")${RESET} │ ${BOLD}$(printf "%-${max_result}s"           "Result")${RESET} │"
echo -e "  ├$(hr $max_repo)┼$(hr $max_trunk)┼$(hr $max_branch)┼$(hr $max_trunk_pulled)┼$(hr $max_branch_updated)┼$(hr $max_stash)┼$(hr $max_result)┤"

for i in "${!col_repo[@]}"; do
  repo="${col_repo[$i]}"
  trunk="${col_trunk[$i]}"
  branch="${col_branch[$i]}"
  trunk_pulled="${col_trunk_pulled[$i]}"
  branch_updated="${col_branch_updated[$i]}"
  stash="${col_stash[$i]}"
  result="${col_result[$i]}"
  type="${col_type[$i]}"

  # Pre-pad all plain strings before applying color so column widths stay correct
  repo_p=$(printf           "%-${max_repo}s"           "$repo")
  trunk_p=$(printf          "%-${max_trunk}s"          "$trunk")
  branch_p=$(printf         "%-${max_branch}s"         "$branch")
  trunk_pulled_p=$(printf   "%-${max_trunk_pulled}s"   "$trunk_pulled")
  branch_updated_p=$(printf "%-${max_branch_updated}s" "$branch_updated")
  stash_p=$(printf          "%-${max_stash}s"          "$stash")
  result_p=$(printf         "%-${max_result}s"         "$result")

  # Indicator and stash columns are colored per-value
  case "$trunk_pulled" in
    "✓") tp_col="${GREEN}${trunk_pulled_p}${RESET}" ;;
    "✗") tp_col="${RED}${trunk_pulled_p}${RESET}"   ;;
    *)   tp_col="${DIM}${trunk_pulled_p}${RESET}"   ;;
  esac

  case "$branch_updated" in
    "✓") bu_col="${GREEN}${branch_updated_p}${RESET}" ;;
    "✗") bu_col="${RED}${branch_updated_p}${RESET}"   ;;
    *)   bu_col="${DIM}${branch_updated_p}${RESET}"   ;;
  esac

  case "$stash" in
    "restored") stash_col="${GREEN}${stash_p}${RESET}"  ;;
    "conflict") stash_col="${RED}${stash_p}${RESET}"    ;;
    *)          stash_col="${DIM}${stash_p}${RESET}"    ;;
  esac

  case "$type" in
    ok)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${CYAN}${branch_p}${RESET} │ ${tp_col} │ ${bu_col} │ ${stash_col} │ ${GREEN}${result_p}${RESET} │"
      ;;
    updated)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${CYAN}${branch_p}${RESET} │ ${tp_col} │ ${bu_col} │ ${stash_col} │ ${GREEN}${result_p}${RESET} │"
      ;;
    skip)
      echo -e "  │ ${DIM}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${DIM}${branch_p}${RESET} │ ${DIM}${trunk_pulled_p}${RESET} │ ${DIM}${branch_updated_p}${RESET} │ ${DIM}${stash_p}${RESET} │ ${YELLOW}${result_p}${RESET} │"
      ;;
    error)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${CYAN}${branch_p}${RESET} │ ${tp_col} │ ${bu_col} │ ${stash_col} │ ${RED}${result_p}${RESET} │"
      ;;
    *)
      echo -e "  │ ${BOLD_WHITE}${repo_p}${RESET} │ ${DIM}${trunk_p}${RESET} │ ${DIM}${branch_p}${RESET} │ ${DIM}${trunk_pulled_p}${RESET} │ ${DIM}${branch_updated_p}${RESET} │ ${DIM}${stash_p}${RESET} │ ${YELLOW}${result_p}${RESET} │"
      ;;
  esac
done

echo -e "  └$(hr $max_repo)┴$(hr $max_trunk)┴$(hr $max_branch)┴$(hr $max_trunk_pulled)┴$(hr $max_branch_updated)┴$(hr $max_stash)┴$(hr $max_result)┘"
echo
echo -e "${BOLD_WHITE}All done!${RESET}"
