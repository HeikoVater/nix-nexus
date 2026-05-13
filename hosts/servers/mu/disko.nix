# ═══════════════════════════════════════════════════════════════════
#  Declarative Disk Layout (disko)
# ═══════════════════════════════════════════════════════════════════
#  Two-tier ZFS storage:
#    rpool (NVMe SSD) — OS state, Nix store, databases
#    tank  (2x HDD mirror) — bulk media, documents, backups
#
#  Root (/) is NOT on disk — it's a tmpfs defined in
#  hardware-configuration.nix. Only /boot, /nix, /persist,
#  and application data live on ZFS.
#
#  ┌─────────────────────────────────────────────────────────┐
#  │  NVMe SSD (~1 TB)                                       │
#  │  ┌──────┬──────┬─────────┬────────────────────────────┐ │
#  │  │ ESP  │ Swap │ L2ARC   │ rpool (ZFS)                │ │
#  │  │ 1 GB │ 8 GB │ 150 GB  │ ~841 GB                    │ │
#  │  └──────┴──────┴─────────┴────────────────────────────┘ │
#  └─────────────────────────────────────────────────────────┘
#  ┌──────────────────────┐  ┌──────────────────────┐
#  │  HDD 1 (12 TB)       │  │  HDD 2 (12 TB)       │
#  │  └─ tank (mirror) ───┘  │  └─ tank (mirror) ───┘
#  └──────────────────────┘  └──────────────────────┘
#
# ─────────────────────────────────────────────────────────────────
{
  disko.devices = {
    disk = {
      # ── NVMe SSD ──────────────────────────────────────────────
      ssd = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_25482X800786";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              priority = 2;
              size = "8G";
              content = {
                type = "swap";
                discardPolicy = "both";
              };
            };
            l2arc = {
              priority = 3;
              size = "150G";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
            main = {
              priority = 4;
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      # ── HDD 1 ────────────────────────────────────────────────
      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST12000VN0008-3MH101_WZ002NTZ";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };

      # ── HDD 2 ────────────────────────────────────────────────
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST12000VN0008-3MH101_WZ0039TW";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    # ═════════════════════════════════════════════════════════════
    #  ZFS Pools
    # ═════════════════════════════════════════════════════════════

    zpool = {
      # ── rpool: SSD "hot" pool ───────────────────────────────
      # Single-disk — no redundancy. Critical data is backed up
      # to tank via BorgBackup. Contains the Nix store, all
      # persistent system/service state, and databases.
      rpool = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          "com.sun:auto-snapshot" = "false";
        };
        mountpoint = null;

        datasets = {
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };

          persist = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
          };

          postgres = {
            type = "zfs_fs";
            mountpoint = "/var/lib/postgresql";
            options = {
              mountpoint = "legacy";
              # Match PostgreSQL's 8 KB page size. ZFS default is
              # 128 KB which causes massive write amplification for
              # database workloads.
              recordsize = "16K";
              # Full data checksums matter more for databases than
              # the small CPU cost.
              compression = "zstd";
              # Pair logical pg_dump backups with short-term ZFS file
              # history so accidental local changes can be undone
              # quickly without waiting on Borg restores.
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };

      # ── tank: HDD "cold" pool ──────────────────────────────
      # 2-wide mirror for redundancy. Stores bulk media,
      # documents, shared files, and backups. The L2ARC on
      # the SSD caches hot metadata + data to reduce HDD I/O
      # and prevent unnecessary disk spin-ups.
      tank = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "mirror";
                members = [
                  "hdd1"
                  "hdd2"
                ];
              }
            ];
            cache = [ "/dev/disk/by-partlabel/disk-ssd-l2arc" ];
          };
        };
        options = {
          ashift = "12";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          "com.sun:auto-snapshot" = "false";
        };
        mountpoint = null;

        datasets = {
          # Important documents, photos — things you never
          # want to lose. Full data + metadata L2ARC caching.
          safe = {
            type = "zfs_fs";
            mountpoint = "/tank/safe";
            options = {
              mountpoint = "legacy";
              compression = "zstd";
              recordsize = "128K";
              secondarycache = "all";
            };
          };

          # Paperless archive and inbox. Split into a child dataset so
          # snapshots and future replication can target documents
          # without pulling in the rest of /tank/safe.
          "safe/paperless" = {
            type = "zfs_fs";
            mountpoint = "/tank/safe/paperless";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Immich originals, thumbnails, and derived media live here.
          # Keeping it in its own dataset gives photos and videos the
          # same snapshot boundary as the database-backed apps.
          "safe/immich" = {
            type = "zfs_fs";
            mountpoint = "/tank/safe/immich";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Syncthing, Samba shared folders — mixed file sizes.
          # Keep the default 128 KiB recordsize, but allow larger dnodes so
          # Samba metadata and xattrs can stay inline more often.
          share = {
            type = "zfs_fs";
            mountpoint = "/tank/share";
            options = {
              mountpoint = "legacy";
              compression = "lz4";
              dnodesize = "auto";
              secondarycache = "all";
            };
          };

          # Jellyfin media library — large video files.
          # 1 MB recordsize reduces fragmentation and metadata
          # overhead for multi-GB files. Only metadata is cached
          # in L2ARC since caching chunks of video data is
          # wasteful.
          media = {
            type = "zfs_fs";
            mountpoint = "/tank/media";
            options = {
              mountpoint = "legacy";
              compression = "lz4";
              recordsize = "1M";
              secondarycache = "metadata";
            };
          };

          # BorgBackup repository. Borg already compresses with
          # zstd, so ZFS compression yields minimal extra benefit
          # but doesn't hurt. Only metadata is cached since
          # backup archives are rarely read randomly.
          backups = {
            type = "zfs_fs";
            mountpoint = "/tank/backups";
            options = {
              mountpoint = "legacy";
              compression = "zstd";
              recordsize = "128K";
              secondarycache = "metadata";
            };
          };
        };
      };
    };
  };
}
