# Kernel Work CLI

`kernel-work` is a comprehensive suite of developer tools designed for Linux kernel engineers at SUSE. It automates and streamlines the complex workflows associated with cherry-picking patches from upstream Linux repositories, backporting them to SUSE `kernel-source` packages, verifying builds/kABI, and fetching, tracking, and resolving CVEs from SUSE Bugzilla.

---

## Table of Contents

- [Architecture & Dependencies](#architecture--dependencies)
  - [cli_class_tool Gem Dependency](#cli_class_tool-gem-dependency)
  - [workEnv Integration](#workenv-integration)
- [System Requirements & Setup](#system-requirements--setup)
  - [Required Git Repositories](#required-git-repositories)
  - [Environment Variables](#environment-variables)
  - [Recommended Setup: Bare Clones & `git worktree` with `workEnv`](#recommended-setup-bare-clones--git-worktree-with-workenv)
  - [Branch Naming Convention](#branch-naming-convention)
  - [Configuration File (`config.yml`)](#configuration-file-configyml)
- [Daily Workflow for Regular Patches](#daily-workflow-for-regular-patches)
  - [1. Identifying Recommended Fixes (`kernel git_fixes`)](#1-identifying-recommended-fixes-kernel-git_fixes)
  - [2. Cherry-picking and Extracting (`kernel scp`)](#2-cherry-picking-and-extracting-kernel-scp)
    - [Subshell Conflict Resolution](#subshell-conflict-resolution)
    - [Checkpatch & Meld Tuning Loop](#checkpatch--meld-tuning-loop)
- [Service Pack (SP) Workflow](#service-pack-sp-workflow)
  - [1. Configuration Filters](#1-configuration-filters)
  - [2. Identifying Missing Patches (`kernel backport_todo`)](#2-identifying-missing-patches-kernel-backport_todo)
  - [3. Batch Apply with State File Management](#3-batch-apply-with-state-file-management)
- [CVE Workflow](#cve-workflow)
  - [1. Update Remote Branches](#1-update-remote-branches)
  - [2. Fetch CVE Bugs (`kernel cve fetch`)](#2-fetch-cve-bugs-kernel-cve-fetch)
  - [3. List CVE Status (`kernel cve ls`)](#3-list-cve-status-kernel-cve-ls)
  - [4. Apply CVE Fixes (`kernel cve apply`)](#4-apply-cve-fixes-kernel-cve-apply)
  - [5. Push and Sync (`kernel cve push`)](#5-push-and-sync-kernel-cve-push)
  - [6. Manual Status Refreshes (`kernel cve refresh`)](#6-manual-status-refreshes-kernel-cve-refresh)
- [Other Key Utilities & Commands](#other-helpful-utilities--commands)
  - [Configuration & Filter Management](#configuration--filter-management)
  - [SUSE kernel-source Specific Commands](#suse-kernel-source-specific-commands)
  - [Upstream Linux Specific Commands](#upstream-linux-specific-commands)
- [Shell Autocompletion](#shell-autocompletion)

---

## Architecture & Dependencies

`kernel-work` is built in Ruby as a modular toolset. Commands are grouped under namespaces based on their target:
* **Upstream Operations:** Executed on your local upstream Linux repository.
* **SUSE Operations:** Executed on your local `kernel-source` package repository.
* **CVE Operations:** Cross-repository and API-driven workflows centered around security bugs.

### `cli_class_tool` Gem Dependency

`kernel-work` and `workEnv` both depend on the **`cli_class_tool`** gem for action routing, option parsing, and logging. 

* **Installation:** Install it via bundler or directly:
  ```bash
  gem install cli_class_tool
  gem install workEnv
  ```

### workEnv Integration

The tool features native integration with **`workEnv`** (managed via the `WorkEnvs` module).

#### Why use workEnv?
For kernel development, **`workEnv` is used to create lightweight, isolated shell workspaces (functioning like "chroots") for different release branches**. Use simple, empty `dev` environments.

Sourcing or switching into an environment spawns a clean, isolated Bash subshell that provides:
* **Prompt Isolation:** A dedicated prefix in your terminal prompt (e.g., `(SLE15-SP6) [user@host pwd]$`) indicating your active workspace.
* **Custom Environment Variables:** Isolated definitions for `$LINUX_GIT` and `$KERNEL_SOURCE_DIR` tailored to that specific branch.
* **Independent Configurations:** Dedicated shell configurations sourced automatically on entry from `$XDG_CONFIG_HOME/workEnv/bashrcs/`.
* **Zero Inter-Branch Pollution:** Clean context-switching between different kernel releases (e.g. `SLE15-SP6-LTSS`, `SLE15-SP7`, `SL-16.0`) in different tabs, with independent paths and variables.

#### How it works
When `kernel-work` starts, it checks if the `WORK_ENV_SCRIPTS_DIR` environment variable is defined. If so, it appends `#{ENV['WORK_ENV_SCRIPTS_DIR']}/lib` to the Ruby `$LOAD_PATH` and attempts to load `WorkEnvs`.

#### Exposed Subcommands
If `workEnv` is loaded successfully, the nested subcommand `env` is registered under the `kernel` command, making environment management commands available directly:
* `kernel env create` (alias: `kernel cr`, `kernel create`) — Create a new empty development workspace.
  * **Tip:** Creating a simple `dev` environment is as easy as running:
    ```bash
    kernel env create -n SLE15-SP6 -t dev
    ```
* `kernel env switch` (alias: `kernel s`, `kernel sw`, `kernel switch`) — Switch into your development workspace.
  * **Tip:** This spawns an isolated Bash subshell. Type `exit` (or `Ctrl+D`) to exit the workspace and return to your parent shell.
    ```bash
    kernel env switch SLE15-SP6
    ```
* `kernel env list` (alias: `kernel l`, `kernel list`) — List existing development workspaces.
  ```bash
  kernel env list
  ```

---

## System Requirements & Setup

Before running `kernel-work`, ensure your environment meets the following structure and configuration requirements.

### Required Git Repositories

You must maintain two distinct, cloned Git repositories on your local system:
1. **Linux Kernel Git Clone (`LINUX_GIT`):** A checkout of the upstream Linux kernel repository (with remotes configured for maintainer trees, e.g., `linux-rdma`).
2. **SUSE `kernel-source` Package Clone (`KERNEL_SOURCE_DIR`):** A checkout of the SUSE kernel-source package repository.

### Environment Variables

Your shell profile (e.g., `.bashrc`, `.zshrc`) must define the environment variables pointing to these clones. By default, `kernel-work` looks for:
```bash
export LINUX_GIT="/path/to/your/linux-upstream-clone"
export KERNEL_SOURCE_DIR="/path/to/your/suse-kernel-source-clone"
```
*(Note: If you use custom env names, you can customize them in the config file using `linux_git_env_var` and `kernel_source_dir_env_var` keys).*

### Recommended Setup: Bare Clones & `git worktree` with `workEnv`

To avoid duplicating massive Git repository files (especially the upstream Linux history) and to speed up workspace creation, **it is highly recommended to maintain a single "bare" clone for each repository and deploy branch-specific checkouts in each `workEnv` using `git worktree`**.

This enables you to have a single physical repository on your disk, but have different branches always checked out in their respective isolated `workEnv` folders.

#### Step 1: Create Your Bare Clones
Clone the repositories as "bare" (no working directory, purely the database) somewhere on your local storage:
```bash
# Clone upstream Linux as a bare repo
git clone --bare git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git /work1/$(whoami)/git/linux.git

# Clone SUSE kernel-source as a bare repo
git clone --bare <suse-kernel-source-remote-url> /work1/$(whoami)/git/kernel-source.git
```

#### Step 2: Create Your workEnvs
Create empty `dev` environments corresponding to the target releases you work on:
```bash
kernel env create -n SLE15-SP6 -t dev
kernel env create -n SLE15-SP7 -t dev
```

#### Step 3: Deploy Worktrees inside each workEnv
From your bare repository directories, use `git worktree` to check out target branches directly inside your `workEnv` folder. They will share the same physical database and object store, meaning creation is instantaneous and uses near-zero extra disk space:

```bash
# --- For the SLE15-SP6 Workspace ---
cd /work1/$(whoami)/git/linux.git
git worktree add /work1/$(whoami)/work-envs/SLE15-SP6/linux <SLE15-SP6-upstream-branch-or-tag>

cd /work1/$(whoami)/git/kernel-source.git
git worktree add /work1/$(whoami)/work-envs/SLE15-SP6/kernel-source <SLE15-SP6-suse-branch>

# --- For the SLE15-SP7 Workspace ---
cd /work1/$(whoami)/git/linux.git
git worktree add /work1/$(whoami)/work-envs/SLE15-SP7/linux <SLE15-SP7-upstream-branch-or-tag>

cd /work1/$(whoami)/git/kernel-source.git
git worktree add /work1/$(whoami)/work-envs/SLE15-SP7/kernel-source <SLE15-SP7-suse-branch>
```

#### Step 4: Configure workEnv Auto-Variables
You can configure `workEnv` to dynamically route your `$LINUX_GIT` and `$KERNEL_SOURCE_DIR` environment variables to point to the correct worktrees automatically upon entering the workspace.

Create/edit the workspace-specific shell profile under your `workEnv` config directory:

* For **`SLE15-SP6`** (`~/.config/workEnv/bashrcs/SLE15-SP6`):
  ```bash
  export LINUX_GIT="/work1/$(whoami)/work-envs/SLE15-SP6/linux"
  export KERNEL_SOURCE_DIR="/work1/$(whoami)/work-envs/SLE15-SP6/kernel-source"
  ```

* For **`SLE15-SP7`** (`~/.config/workEnv/bashrcs/SLE15-SP7`):
  ```bash
  export LINUX_GIT="/work1/$(whoami)/work-envs/SLE15-SP7/linux"
  export KERNEL_SOURCE_DIR="/work1/$(whoami)/work-envs/SLE15-SP7/kernel-source"
  ```

#### How it Behaves
Now, whenever you run `kernel env switch SLE15-SP6` or `kernel sw SLE15-SP6`, the shell environment automatically points to the correct SLE15-SP6 directories, prompt, and branches. If you switch to another workspace (even in another tab), the variables automatically redirect to the SLE15-SP7 directories. 

You maintain **only one single physical copy of the repository files on disk**, but all branches are checked out simultaneously without duplication!

### Branch Naming Convention

`kernel-work` dynamically maps local working directories to their correct SUSE release baselines by parsing your current local branch name. To make this possible, **your working branches in both repositories must follow a slash-delimited convention**:

```
<arbitrary-prefix>/<optional-subprefix>/<suse-base-branch>/<topic-suffix>
```

* **Where `<suse-base-branch>`** must correspond to one of the supported branch names in your `config.yml` file (e.g., `SLE15-SP6-LTSS`, `SLE15-SP7`, `SL-16.0`, `cve/linux-5.14-LTSS`).
* **Example:** `user/nmorey/work/SLE15-SP6-LTSS/for-next`
  * The tool parses this and extracts the base branch: `SLE15-SP6-LTSS`.
  * This matches configured release characteristics (such as the default patch paths, compiler rules, and series files).

### Configuration File (`config.yml`)

`kernel-work` settings are managed via YAML. 

* **Default Location:** `~/.config/kernel-work/config.yml` (respects `$XDG_CONFIG_HOME` if set).
* **Generating Defaults:** To generate a template config containing standard SUSE branches, upstream configurations, compiler rules, and CVE tracking defaults, run:
  ```bash
  kernel --force-config # Or kernel -f
  ```
* **Alternate Config Path:** Specify an alternate config file on any command run with:
  ```bash
  kernel -c /path/to/alternate-config.yml <command>
  ```

---

## Daily Workflow for Regular Patches

For everyday backporting tasks, the workflow revolves around pulling recommended fixes, cherry-picking them in your upstream tree, and exporting them cleanly to your SUSE packaging branch.

### 1. Identifying Recommended Fixes (`kernel git_fixes`)

To automatically check the SUSE upstream fixes tracker for recommended patches targeting your current branch's subsystem (e.g., `infiniband`):
```bash
kernel git_fixes [-s <subtree>] [-l]
```
* **What it does:** Fetches the list of recommmended fixes from the configured tracker (e.g., `git_fixes_url`). It displays the list of recommendations and classifies them as `APPLIED` (already in your SUSE patch directory) or `PENDING`.
* **Interactive Scp:** Unless you pass the `--list-only` (`-l`) flag, the tool will automatically queue the `PENDING` commits and prompt you to run the `scp` command to backport them.

### 2. Cherry-picking and Extracting (`kernel scp`)

The cornerstone command of the tool is `scp` (Secure Cherry Pick). It automates the cherry-pick, conflict management, patch creation, series registration, and checkpatch verification in one clean, interactive pass:

```bash
# Backport a single commit
kernel scp -c <upstream-SHA1>

# Backport multiple commits listed in a text file (one SHA per line)
kernel scp -f <file-containing-SHAs>

# Auto-extract reference bug tracking metadata from security lists
kernel scp -C -c <upstream-SHA1>
```

#### Interactive Prompt & Series Queuing
Before cherry-picking each commit, `kernel scp` displays commit metadata, checks whether the patch fixes backported or unbackported commits, and queries public-inbox archives to determine if the commit is part of an upstream patch series. It then presents an interactive confirmation prompt:

```text
Do you wish to pick commit '<sha> ("<subject>")' up (a=queue series) ? (y/n/?/r/a):
```

* **`y` (yes):** Proceed with cherry-picking and extracting the current commit.
* **`n` (no):** Skip the current commit and move to the next commit in the queue.
* **`?` (show):** Launch `git show <sha>` interactively to inspect the commit diff and log message.
* **`r` (ref):** Prompt for a bug or CVE tracking reference (e.g. `bsc#1234567`) to attach to the extracted SUSE patch.
* **`a` (all in series):** Available when the patch is part of a multi-patch series. Dequeues the current commit and prepends all sibling patches in the series in proper sequence into the work queue (deduplicating against already queued entries). Patches in the series that are already applied in the tree are automatically detected and skipped.

#### Subshell Conflict Resolution
If a git cherry-pick fails with merge conflicts in your upstream `LINUX_GIT` repository:
1. `kernel-work` pauses and prints a warning.
2. It **enters an interactive subshell** with the prompt marked `[SCP FIX]`.
3. You can safely run standard git commands, resolve conflicts, and test changes in this subshell.
4. **Exit the subshell** (`exit` or `Ctrl+D`) when done.
5. The tool will prompt you: `continue with scp [y(es), n(o), s(kip)]?`
   * `y` commits the resolved cherry-pick and proceeds.
   * `s` aborts and skips this specific patch.
   * `n` aborts the entire `scp` chain.

#### Checkpatch & Meld Tuning Loop
Once a cherry-pick succeeds in `LINUX_GIT`, `kernel-work` automatically:
1. Extracts the commit into a SUSE formatted patch file (e.g., under `patches.suse/`).
2. Registers the patch file in `series.conf`.
3. Commits the changes in your `KERNEL_SOURCE_DIR`.
4. Formats the commit and runs the SUSE kernel's `checkpatch` script (`sequence-patch`).
5. **If checkpatch fails:** The tool opens a `meld` GUI window comparing your newly created `patches.suse/` patch with the formatted git patch `0001-*.patch`.
   * You can edit/meld the patch file inside `meld` to address checkpatch/formatting warnings.
   * Save and close `meld`.
   * The tool automatically re-adds the patch file, runs `git commit --amend`, and runs checkpatch again.
   * This loops dynamically until checkpatch passes or you accept the formatting.

---

## Service Pack (SP) Workflow

During the development and maintenance of SUSE Service Packs (e.g., preparing fixes for a new SP release), engineers often need to identify and backport a large batch of missing upstream commits for their subsystem. This is managed via the **SP Workflow** using `kernel backport_todo` and **saved filters**.

### 1. Configuration Filters

When working on a specific subsystem (e.g., `infiniband`), you don't want to scan the entire Linux kernel git history. Filters allow you to narrow down the scanned commits to only your files of interest, specific authors, or commit messages.

#### Defining and Saving a Filter
You can define a saved filter named `ib` that tracks the `drivers/infiniband` and `include/rdma` directories, skipping generic treewide cleanups:

```bash
kernel config filter add --filter ib \
  -p drivers/infiniband \
  -p include/rdma \
  -e drivers/infiniband/hw/hns \
  -T
```

* `-p, --path`: Subtree to monitor for missing patches (can be specified multiple times).
* `-e, --exclude-path`: Subtree to exclude from the monitor.
* `-T, --skip-treewide`: Skip massive treewide commits that happen to touch files in your path.
* Other options: `-F` (only commits with a `Fixes:` tag), `-g <pattern>` (grep commit message), `--author <author>`.

### 2. Identifying Missing Patches (`kernel backport_todo`)

Once your filter is set up, use the `backport_todo` command to inspect which upstream patches are in the reference upstream branch but have not been backported to your current SUSE branch:

```bash
kernel backport_todo --filter ib
```

* **How it works:** It generates two lists:
  1. The upstream commit list (from `origin/master` or `-R <upstream-ref>`) matching your filter.
  2. Your local applied commit list (from your SUSE branch) matching your filter.
* It compares the patch IDs (and the `Git-commit:` headers of all applied patches under `patches.suse/`) to subtract already applied patches.
* It displays the resulting missing patches on the terminal in correct chronological order.

#### Customizing the Scan Window
You can control the comparison baseline using reference parameters:
```bash
# Compare against a specific upstream branch or tag instead of origin/master
kernel backport_todo --filter ib -R v6.6

# Compare from a different starting base point instead of your current HEAD
kernel backport_todo --filter ib -B SLE15-SP6-LTSS
```

### 3. Batch Apply with State File Management

The most efficient and suggested way to perform batch backports is to run the **`backport_todo`** command with the **`--apply`** (or **`-A`**) flag alongside the **`-f <FILE>`** option:

```bash
kernel backport_todo --filter ib --apply -f my_todo_list.txt [-S]
```

* **How it works under the hood:**
  1. **Generates and Exports:** The command identifies all missing patches according to your filter and writes them in correct reverse-chronological order into `my_todo_list.txt`.
  2. **Triggers SCP Loop:** It immediately and seamlessly transitions to the `scp` engine to begin backporting the listed commits one by one.
  3. **Maintains State in the File:** If a merge conflict is encountered or you choose to skip or abort, **the remaining unhandled commits are written back to `my_todo_list.txt`**.
  4. **Resuming Work:** This state management allows you to resume exactly where you left off by simply running:
     ```bash
     kernel scp -f my_todo_list.txt
     ```

---

## CVE Workflow

The CVE workflow automates fetching security advisories assigned to you, analyzing backport targets, applying fixes to multiple releases, and updating status flags.

### 1. Update Remote Branches
Ensure your local `KERNEL_SOURCE_DIR` remote tracking branches are up to date so status checks are accurate:
```bash
cd $KERNEL_SOURCE_DIR
git remote update
```

### 2. Fetch CVE Bugs (`kernel cve fetch`)
Fetch active CVE tracking bugs assigned to you directly from SUSE Bugzilla:
```bash
kernel cve fetch [-u <bugzilla-email>] [-f]
```
* **What it does:** Authenticates using your Bugzilla credentials (defined in `config.yml` or overridden via `-u`). It downloads all open kernel CVE bugs, parses their descriptions/comments to extract upstream main branch SHAs and target release backport details, and stores/updates them in your local tracker database (configured in `cve.data_repo`).
* **Cache Cleanup:** Reassigned or resolved CVEs are automatically detected and pruned from your local cache on fetch. Pass `--force` (`-f`) to completely wipe the local tracking data and re-fetch from scratch.

### 3. List CVE Status (`kernel cve ls`)
Review your active CVE queue and status matrix across all target SUSE release branches:
```bash
kernel cve ls # Or kernel cve status
```
* **What it does:** Displays a beautiful, colored status matrix mapping each active CVE/Bug ID to its status on each target branch:
  * `TODO` (Red) — Not yet applied.
  * `APPLIED` (Yellow) — Applied locally but not pushed.
  * `PUSHED` (Blue) — Pushed to remote but not merged.
  * `MERGED` (Green) — Fully merged into the remote branch baseline.

### 4. Apply CVE Fixes (`kernel cve apply`)
Attempt to automatically backport, apply, and compile all pending CVE fixes on your current working branch:
```bash
kernel cve apply [-y] [-a <arch>] [-j <jobs>]
```
* **What it does:** Scans your local tracker database for all CVEs targeting your current active SUSE branch that are currently marked as `TODO`.
* It calls the `scp` engine to sequentially cherry-pick, extract, and apply each relevant upstream fix patch.
* After applying, it builds the affected subsystem (using `-a` and `-j` for parallel compiler execution) to ensure no compilation issues were introduced.
* If a patch is applied successfully, its status in the tracker is updated to `APPLIED`.

### 5. Push and Sync (`kernel cve push`)
Once you are confident with your local CVE fixes, push them to the SUSE remote and synchronize state:
```bash
kernel cve push [-f]
```
* **What it does:** Scans your unpushed commits on the current branch for referenced Bugzilla Bug IDs (e.g., `bsc#123456`).
* Pushes the current branch to your configured SUSE git remote.
* Runs a status refresh to update all successfully pushed CVE tracker statuses from `APPLIED` to `PUSHED` (or `MERGED` if applicable).

### 6. Manual Status Refreshes (`kernel cve refresh`)
To manually force-recalculate the status of CVEs on the current branch based on current git logs (checking what's applied locally, unpushed, pushed, or merged):
```bash
kernel cve refresh
```

---

## Other Key Utilities & Commands

`kernel-work` includes several utility modules to assist with config files, filters, and repository management.

### Configuration & Filter Management

Manage your global and project settings from the CLI:
* `kernel config show` — Print currently active configuration settings in YAML.
* `kernel config diff` — Compare active configuration against global tool defaults.
* **Saved Filters:** Filters let you monitor specific subtrees, authors, or subjects for missing patches:
  * `kernel config filter add --filter <name> -p <path> [-e <exclude-path>] [-g <grep>] [-fixes]` — Save a named filter.
  * `kernel config filter list` — List all saved filters.
  * `kernel config filter show --filter <name>` — Inspect saved filter properties.
  * `kernel config filter delete --filter <name>` — Delete a saved filter.
* **Registered Branches:**
  * `kernel config branch add -b <name> [-r <default-ref>] [--no-sorted-series]` — Register a SUSE release branch.
  * `kernel config branch list` — List all registered release branches.
  * `kernel config branch delete -b <name>` — Unregister a branch.

### SUSE kernel-source Specific Commands

The following commands operate specifically on the `KERNEL_SOURCE_DIR` checkout:
* `kernel source_rebase [-A] [-I]` — Rebase the current branch to its remote tip. Pass `-A` to attempt to automatically fix any `series.conf` merge conflicts using `fix_series`. Pass `-I` to run non-interactively.
* `kernel fix_series` — Auto-resolve common conflicts in `series.conf` during rebases.
* `kernel checkpatch [-F]` — Run a rapid checkpatch on all pending patches on the current branch (pass `-F` for a slower, complete check).
* `kernel list_commits` (alias: `kernel lc`) — List pending local commits (supports `--unpushed` and `--unmerged`).
* `kernel check_fixes` — Detects missing git-fixes for patches already committed in the SUSE branch.
* `kernel fix_mainline` — Corrects the `Git-mainline` tag in the most recent commit.
* `kernel fix_ref -r <ref>` — Updates or fixes the reference tag (e.g., `bsc#ID`) in the last commit.
* `kernel meld_lastpatch` — Open `meld` to compare the last committed patch file with upstream `0001-*.patch` and amend it.
* `kernel extract_patch -c <SHA> [-r <ref>]` — Picks a patch from `LINUX_GIT` and commits it to `KERNEL_SOURCE_DIR`.

### Upstream Linux Specific Commands

The following commands operate specifically on the `LINUX_GIT` checkout:
* `kernel apply_pending` — Hard reset the upstream branch to its SUSE tracking remote tip and re-apply all local patches registered in `KERNEL_SOURCE_DIR`.
* `kernel oldconfig [-a <arch>]` — Copy the configuration file from `KERNEL_SOURCE_DIR` to `LINUX_GIT` and run `make oldconfig`.
* `kernel build [-p <path>] [-I] [-j <jobs>]` — Build the kernel, or a subset/subtree (e.g., pass `-I` to build the infiniband subtree only).
* `kernel kabi_check [-a <arch>]` — Check the kABI compatibility of your current kernel build using the SUSE `kabi.pl` script.
* `kernel backport_todo [-R <upstream-ref>] [-B <base-ref>] [-A]` — Detects commits in `origin/master` that are missing in your SUSE branch. Pass `-A` to automatically launch an `scp` loop to backport all missing patches.

---

## Shell Autocompletion

To enable robust, context-aware command line autocompletion for `kernel-work` (including dynamic options, branch names, and saved filters), source the completion script in your shell configuration:

```bash
# Add to your ~/.bashrc or ~/.profile
if [ -f /path/to/kernel-work/kernel-work-completion.sh ]; then
    . /path/to/kernel-work/kernel-work-completion.sh
fi
```
Once sourced, pressing `Tab` after typing `kernel` will dynamically suggest actions, flags, registered branches, or filter names based on your typing context!
