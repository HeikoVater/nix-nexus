# Restore Runbook

This runbook covers operator-driven restores on a host that is still up and can
read its local Borg repository. It assumes you are working from a checkout of
this repo and that you stop affected services before overwriting live state.

Local Borg archives help with accidental deletion, bad upgrades, and recent app
mistakes on a still-working machine. They do not replace off-host disaster
recovery.

## Contents

- [Common Variables](#common-variables)
- [Restore A File From Borg](#restore-a-file-from-borg)
- [PostgreSQL Restore Order](#postgresql-restore-order)
- [Restore Paperless](#restore-paperless)
- [Restore Immich](#restore-immich)
- [ZFS Snapshots Versus Borg](#zfs-snapshots-versus-borg)

## Common Variables

Run these from the repo root before following the restore steps below:

```sh
HOST=<hostname>
ARCHIVE=<hostname>-YYYY-MM-DDTHH:MM:SS
BORG_WRAPPER="borg-job-${HOST}"
RESTORE_ROOT="$(mktemp -d)"

PAPERLESS_STORAGE_ROOT="$(nix eval ".#nixosConfigurations.${HOST}.config.homelab.paperless.storageRoot" --raw)"
PAPERLESS_DATA_DIR="$(nix eval ".#nixosConfigurations.${HOST}.config.homelab.paperless.dataDir" --raw)"
IMMICH_MEDIA_ROOT="$(nix eval ".#nixosConfigurations.${HOST}.config.homelab.immich.mediaLocation" --raw)"

trap 'rm -rf "$RESTORE_ROOT"' EXIT
```

If you are restoring on the backed-up host, use `sudo "$BORG_WRAPPER" ...` so
the wrapper can read the encrypted repo and its passphrase automatically. If
you copied the repo elsewhere, use plain `borg` with the repo path and
passphrase instead.

## Restore A File From Borg

1. List available archives and pick the one you need.
2. Find the exact path inside that archive.
3. Extract the file into a temporary directory.
4. Copy it back into place.

```sh
sudo "$BORG_WRAPPER" list --short
sudo "$BORG_WRAPPER" list --format '{path}{NL}' "::${ARCHIVE}" | grep '<path-fragment>'

(
  cd "$RESTORE_ROOT"
  sudo "$BORG_WRAPPER" extract "::${ARCHIVE}" tank/safe/immich/path/to/file
)

sudo install -D -m 0644 \
  "$RESTORE_ROOT/tank/safe/immich/path/to/file" \
  "/absolute/restore/target"
```

Use `cp -a` instead of `install` when you want to keep the original filename or
restore a full directory tree.

## PostgreSQL Restore Order

Restore PostgreSQL globals first, then restore individual databases.

This order matters because the globals dump recreates shared roles and
privileges before the per-database dumps are loaded.

```sh
gunzip -c "$RESTORE_ROOT/var/backup/postgresql/globals.sql.gz" | sudo -u postgres psql postgres
gunzip -c "$RESTORE_ROOT/var/backup/postgresql/paperless.sql.gz" | sudo -u postgres psql postgres
gunzip -c "$RESTORE_ROOT/var/backup/postgresql/immich.sql.gz" | sudo -u postgres psql postgres
```

The Paperless and Immich dumps are created with `--clean --if-exists --create`,
so piping them into `psql postgres` drops and recreates the target database
before loading its data.

## Restore Paperless

```sh
sudo systemctl stop paperless-{scheduler,task-queue,web,consumer}.service

(
  cd "$RESTORE_ROOT"
  sudo "$BORG_WRAPPER" extract "::${ARCHIVE}" \
    tank/safe/paperless \
    var/lib/paperless \
    var/backup/postgresql/globals.sql.gz \
    var/backup/postgresql/paperless.sql.gz
)

sudo rsync -aHAX --delete "$RESTORE_ROOT/tank/safe/paperless/" "${PAPERLESS_STORAGE_ROOT}/"
sudo rsync -aHAX --delete "$RESTORE_ROOT/var/lib/paperless/" "${PAPERLESS_DATA_DIR}/"

gunzip -c "$RESTORE_ROOT/var/backup/postgresql/globals.sql.gz" | sudo -u postgres psql postgres
gunzip -c "$RESTORE_ROOT/var/backup/postgresql/paperless.sql.gz" | sudo -u postgres psql postgres

sudo systemctl start paperless-{scheduler,task-queue,web,consumer}.service
```

After startup, verify that the web UI loads, documents appear, and the consumer
queue can ingest a test file.

## Restore Immich

```sh
sudo systemctl stop immich-server.service immich-machine-learning.service

(
  cd "$RESTORE_ROOT"
  sudo "$BORG_WRAPPER" extract "::${ARCHIVE}" \
    tank/safe/immich \
    var/lib/immich \
    var/backup/postgresql/globals.sql.gz \
    var/backup/postgresql/immich.sql.gz
)

sudo rsync -aHAX --delete "$RESTORE_ROOT/tank/safe/immich/" "${IMMICH_MEDIA_ROOT}/"
sudo rsync -aHAX --delete "$RESTORE_ROOT/var/lib/immich/" /var/lib/immich/

gunzip -c "$RESTORE_ROOT/var/backup/postgresql/globals.sql.gz" | sudo -u postgres psql postgres
gunzip -c "$RESTORE_ROOT/var/backup/postgresql/immich.sql.gz" | sudo -u postgres psql postgres

sudo systemctl start immich-server.service immich-machine-learning.service
```

After startup, verify that the UI loads and recent assets appear. If you later
trim derived data such as `thumbs` from backups, restore the database and media
first and let Immich regenerate previews afterward.

## ZFS Snapshots Versus Borg

In the current server layout, short-horizon ZFS snapshots are enabled for:

- `rpool/postgres`
- `tank/safe/paperless`
- `tank/safe/immich`

List them with:

```sh
zfs list -t snapshot | grep -E 'rpool/postgres|tank/safe/(paperless|immich)'
```

Use snapshots when the damage is recent, the host and pools are healthy, and
the affected state lives entirely inside one snapshotted dataset.

Prefer Borg when you need older history, need to restore PostgreSQL roles and
databases in a controlled order, or need to recover a service that spans
multiple datasets.

Use `zfs rollback` only when you intend to revert an entire dataset and have
already stopped dependent services. It is destructive to newer writes on that
dataset.
