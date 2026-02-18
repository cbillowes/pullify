# Pullify

Pullify is a utility suite to help keep your Git repositories in a given directory up to date.
This is useful if you have directories that contain multiple Git repositories and you want to quickly check their status or pull the latest changes without having to navigate into each repository individually.

## Installation

Clone the repository to any location on your hard drive.

## Usage

The `pullify` script is the main entry point for using the utility. It supports the following commands:

- `scan`: Scans the specified directory for Git repositories and prints their status.
- `init`: Initializes the repository configuration by scanning the specified directory for Git repositories and creating a configuration file.
- `status`: Shows the current status of all repositories based on the configuration file.
- `pull`: Pulls the latest changes for all repositories based on the configuration file.

It expects a `--path` switch to specify the directory containing the repositories.
The path can either be absolute or relative to the current working directory.

For example:

```bash
./pullify init --path /path/to/repos
```

### Scan

Scan will look for all Git repositories in the specified directory and print their status.
This is useful for quickly checking which repositories have changes that need to be pulled.

### Init

Init will initialize the repository configuration by scanning the specified directory for Git repositories and creating a configuration file.
This configuration file is used by other commands to determine which repositories to manage.

### Status

Status will show the current status of all repositories based on the configuration file.
This includes information about which repositories have changes that need to be pulled.

### Pull

Pull will pull the latest changes for all repositories based on the configuration file.
This ensures that all repositories are up to date with their remote counterparts.

## Configuration

All repos are bundled in text files housed in the `repos` directory.
Each text file corresponds to a parent directory that contains Git repositories.
The text file lists the repositories, their current branches, and whether they should be skipped or not.

```text
<path/to/repo/dir>:<branch>:<skip>
```

For example:

```text
/User/user/workspace/personal:main:
/User/user/workspace/work:main:skip
```
