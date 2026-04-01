# CLAUDE.md — fs-tools

## Project Overview

**fs-tools** is a bash-based full partition image backup suite for headless Debian-based Linux servers. It uses `fsarchiver` to create and restore compressed partition archives, and `sgdisk`/`sfdisk` to back up and restore partition tables.

Scripts: `fs-backup`, `fs-restore`, `fs-list`, `fs-delete`, `fs-shared`.

Development is done on a local machine. Deployment to target servers uses `fs-deploy.sh`, which copies files via `scp` and runs `fs-install.sh` remotely via `ssh -t rod@<target>`.

Target servers: **boss** (Debian 13, Docker, Nextcloud/Home Assistant) and **shrek** (Debian 13, Docker, Caddy/Pi-hole). Remote user is `rod`.

---

## Coding Standards

### `local` Variable Declarations

- Declare **one variable per line** — never collapse multiple declarations onto one line.
- Always declare `local` variables **at the top of the function**, before any logic. Bash has no block scoping.
- **Never combine `local` with command substitution** — this masks the exit code of the subshell.

```bash
# CORRECT
local result
result=$(some_command)
if [ $? -ne 0 ]; then ...

# WRONG — exit code of some_command is lost
local result=$(some_command)
```

### Quoting

- Quote all variable expansions unless intentionally word-splitting.

### sudo and I/O Redirection

- `sudo` does not elevate shell-level I/O redirection operators (`>`, `>>`).
- Use the `sudo tee` pattern for writing to privileged paths:

```bash
# CORRECT
echo "$content" | sudo tee /privileged/path > /dev/null

# WRONG — redirection runs as the calling user, not root
sudo echo "$content" > /privileged/path
```

### Functions

- Functions belong in `fs-shared.sh` **only if actually used by more than one script**.
- Do not preemptively move functions to the shared library in anticipation of future reuse.
- Keep script-specific functions in the script that uses them.

---

## Architecture Conventions

### Directory Structure

Archives are stored under a hostname-based subdirectory:

```
<backup_mount>/
  fs/
    <hostname>/
      <timestamp>/          # e.g., 20250401_143022
        info.json
        pt-type             # contains "gpt" or "dos"
        disk-pt.gpt         # GPT partition table backup (sgdisk)
        disk-pt.sf          # DOS partition table backup (sfdisk)
        <suffix>.fsa        # fsarchiver archive per partition
```

The `<suffix>` in `.fsa` filenames is the partition designator with the disk prefix stripped (e.g., for disk `/dev/sda`, partition `/dev/sda2` produces `2.fsa`).

Hostname is used for subdirectory paths (human-readable, stable). `/etc/machine-id` is the authoritative per-machine identity used for restore verification.

### Partition Table Backup

`backup_partition_table` saves the partition table and records its type:

- GPT disks: `sgdisk --backup` → `disk-pt.gpt`; `pt-type` contains `gpt`
- DOS disks: `sfdisk --dump` → `disk-pt.sf`; `pt-type` contains `dos`

At restore time, `pt-type` is read first to determine which restore method to use before any `.fsa` files are touched.

### Partition Selection

`select_backup_partitions` filters partitions by supported filesystem types:

```
ext2|ext3|ext4|xfs|btrfs|ntfs|vfat|fat16|fat32|reiserfs
```

By default, the active root partition is excluded. The `--include-active` flag overrides this and forces inclusion (with a warning). The `-A` flag is passed to `fsarchiver` for live (mounted RW) partitions.

### info.json

Generated with `jq -nc`. Fields must be exactly:

```json
{
  "comment": "...",
  "device": "...",
  "uuid": "...",
  "hostname": "...",
  "machine_id": "..."
}
```

Note: `device` and `uuid` refer to the **source disk** (e.g., `/dev/sda`), not individual partitions. `uuid` is the disk-level UUID from `blkid -s UUID -o value "$sourcedisk"`.

Example generation pattern:
```bash
json=$(jq -nc \
  --arg comment "$comment" \
  --arg device "$sourcedisk" \
  --arg uuid "$source_uuid" \
  --arg hostname "$sourcehostname" \
  --arg machine_id "$machine_id" \
  '{comment: $comment, device: $device, uuid: $uuid, hostname: $hostname, machine_id: $machine_id}')
echo "$json" > "$archivepath/$g_infofile"
```

### select_archive Return Value

`select_archive` returns a string in the form `hostname/archivename` (e.g., `boss/20250401_143022`). Callers **must split** this before use:

```bash
archivepath="$g_backuppath/$g_backupdir/$archivesubpath"
archivename="${archivesubpath##*/}"
```

### Machine Identity Check at Restore

- `machine_id` from `info.json` is compared against `/etc/machine-id`.
- A mismatch produces a warning prompt — the user may proceed, but is warned the restore may produce an unbootable or misconfigured system.
- This is not a hard abort.

### fsarchiver Options

Standard options used for backup: `-v -j$(nproc) -Z3`

- `-j$(nproc)` — use all available CPU cores for compression
- `-Z3` — compression level 3
- `-A` — added when the source partition is mounted read-write (live backup)

---

## Shared Libraries

`display.sh` and `device.sh` live in a **separate repository** (`tools`) and are deployed independently to `/usr/local/lib`. Do not modify or duplicate them in this project. They are sourced by `fs-shared.sh`:

```bash
source /usr/local/lib/display.sh
source /usr/local/lib/device.sh
```

---

## Deployment Pattern

- `fs-deploy.sh` copies files from the dev machine to `rod@<target>:~` via `scp`, then invokes `fs-install.sh` remotely via `ssh -t rod@<target>`.
- `fs-install.sh` installs files as root:
  - `fs-shared.sh` → `/usr/local/lib/`
  - Executable scripts → `/usr/local/sbin/` with `.sh` extension stripped
- `ssh -t` is required for TTY allocation when sudo prompts are expected.

---

## External Dependencies

The following tools must be present on target systems:

| Tool | Purpose |
|------|---------|
| `fsarchiver` | Partition archive creation and restore |
| `sgdisk` / `gdisk` | GPT partition table backup and restore |
| `sfdisk` | DOS partition table backup and restore |
| `jq` | info.json generation and parsing |
| `blkid` | Disk UUID extraction |
| `findmnt` | Active root partition detection |
| `lsblk` | Partition and filesystem enumeration |
| `partprobe` | Kernel partition table refresh after restore |
