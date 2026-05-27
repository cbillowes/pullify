# Pullify

Pullify is a CLI utility for managing multiple Git repositories at once. If you work across directories that each contain several repos, pullify lets you check their status, pull the latest changes, and switch back to trunk — all without `cd`-ing into each one.

---

## Installation

Clone the repository anywhere on your machine:

```bash
git clone https://github.com/you/pullify.git ~/tools/pullify
```

Add an alias so `pullify` is available from anywhere:

```bash
# In ~/.zshrc or ~/.bashrc or ~/.aliases
alias pullify="~/tools/pullify/pullify"
```

Reload your shell:

```bash
# Example for zsh
source ~/.zshrc
```

---

## Quick Start

```bash
# 1. Discover repos in a directory and create a config file
pullify init --path ~/Workspace/my-projects

# 2. Check the status of all repos
pullify status --path ~/Workspace/my-projects

# 3. Pull the latest changes for all repos
pullify pull --path ~/Workspace/my-projects
```

---

## Commands

All commands require the `--path` flag pointing to the directory that contains your Git repositories. Paths can be absolute or relative to the current working directory.

### `init`

Scans a directory for Git repositories and generates a configuration file in the `repos/` directory (inside your pullify installation). Run this once to get set up.

```bash
pullify init --path ~/Workspace/my-projects
```

This creates `repos/my-projects.txt` with one line per discovered repository:

```text
/Users/you/Workspace/my-projects/api:main:
/Users/you/Workspace/my-projects/frontend:main:
/Users/you/Workspace/my-projects/docs:main:
```

---

### `scan`

Lists all Git repositories found in the given directory along with their current branch. Unlike `status`, this doesn't use a config file — it discovers repos on the fly.

```bash
pullify scan --path ~/Workspace/my-projects
```

Useful for a quick look or before running `init`.

---

### `status`

Fetches from remote and shows the current state of every repository in the config file.

```bash
pullify status --path ~/Workspace/my-projects
```

For each repository you'll see:

| Column | Description |
| ------ | ----------- |
| Repository | Path to the repo |
| Trunk | The configured trunk branch (e.g. `main`) |
| Branch | The currently checked-out branch |
| Status | Whether the repo is up to date, behind trunk, or behind origin |

Status indicators:

- ✓ — Up to date
- ✗ — Behind (needs a pull)
- ? — Unknown (couldn't determine)

---

### `pull`

Pulls the latest changes for all repositories in the config file. Handles both repos on trunk and repos on feature branches.

```bash
pullify pull --path ~/Workspace/my-projects
```

**What it does per repository:**

- **On trunk**: runs `git pull --rebase` to keep history linear
- **On a feature branch**: merges trunk into the branch, syncs the feature branch with its remote counterpart, and rebases trunk locally
- **Uncommitted changes**: automatically stashed before the pull and restored afterward (conflicts are flagged)

The summary table shows:

| Column | Description |
| ------ | ----------- |
| Repository | Path to the repo |
| Trunk | Configured trunk branch |
| Branch | Currently checked-out branch |
| Trunk | Whether trunk was updated (✓ / ✗ / –) |
| Branch | Whether the current branch was updated (✓ / ✗ / –) |
| Stash | Stash result: restored, conflict, or – |
| Result | Overall outcome: up to date, updated, error, or skipped |

---

### `trunk`

Interactively switches selected repositories back to their configured trunk branch.

```bash
pullify trunk --path ~/Workspace/my-projects
```

Only repos that are **not** already on trunk are shown. You pick which ones to switch:

- Enter space-separated numbers (e.g. `1 3 5`) to select specific repos
- Enter `a` to switch all of them
- Press Enter with no input to cancel

Uncommitted changes are stashed automatically before switching and restored afterward.

---

## Configuration

Configuration files live in the `repos/` directory inside your pullify installation. Each file corresponds to one parent directory and is named after it (e.g. `repos/my-projects.txt`).

**Line format:**

```text
<full/path/to/repo>:<trunk-branch>:<skip>
```

**Examples:**

```text
/Users/you/Workspace/my-projects/api:main:
/Users/you/Workspace/my-projects/frontend:main:
/Users/you/Workspace/my-projects/legacy-service:master:
/Users/you/Workspace/my-projects/archived-repo:main:skip
```

| Field | Description |
| ----- | ----------- |
| `path` | Absolute path to the repository |
| `trunk-branch` | The integration branch for this repo (`main`, `master`, etc.) |
| `skip` | Leave blank to include; set to `skip` to exclude from pull/trunk |

Repos marked `skip` still appear in `status` output but are not touched by `pull` or `trunk`.

---

## Tips

- Edit a config file manually to add, remove, or skip repos without re-running `init`.
- Use `scan` after adding new repos to a directory to see what's there before updating the config.
- `pull` is safe to run even with uncommitted work — changes are stashed and restored automatically.
- Trunk branch names can differ per repo (e.g. `main` for one, `master` for another) — configure them individually in the config file.
