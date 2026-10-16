# VinzOS 0.3 (32-bit and 64-bit)

Linux 6.12 + BusyBox. Boots to a lightweight terminal.
Tools: `vp` (software), `vnet` and `vwifi` (network), `vstorage` (disks), `install-vinzos`, `shutdown`, `reboot`, `help`.

## Build
    gh workflow run build-vinzos && gh run watch
Result: a release with `vinzos-all.zip` containing `vinzos-64bit/` and `vinzos-32bit/`.

## Package server
See the separate `vinzos-repo` project.
