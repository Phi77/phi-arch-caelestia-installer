# PHI Arch + Hyprland + Caelestia Guided Installer

A guided installer for the official Arch Linux Live ISO, targeting UEFI/GPT, Btrfs, GRUB, Hyprland, the stable Caelestia Shell AUR package, `yay` as the AUR helper, Brave (`brave-bin`) as the default browser, and HyprMod (`hyprmod`) for managing Hyprland settings.

## Important limitations

- **Destructive:** the selected whole disk is erased after two typed confirmations. It does not preserve Windows, dual-boot, recovery partitions, or existing data.
- **UEFI only:** boot the USB using its UEFI entry.
- This initial version creates a starter Hyprland config and starts Caelestia Shell, but it does **not** install the full upstream Caelestia dotfiles bundle. It is a base desktop foundation that can be refined after first boot.
- It installs `yay` as the AUR helper, the stable `caelestia-shell` AUR package, `brave-bin`, and `hyprmod` (the Hyprland settings application). Brave is configured as the default handler for HTTP, HTTPS, and HTML files. AUR package recipes are community maintained and can change.
- Arch is rolling release. Package names/dependencies may change, so the first run must be monitored. The script logs to `/var/log/phi-arch-caelestia-*.log` on the live environment; that log is not automatically copied to the installed disk.
- No automated tests against real hardware have been performed. Direct installation carries real data-loss risk. Back up first and disconnect all disks except the intended target where possible.

## Requirements

- Current official Arch Linux ISO booted in UEFI mode.
- Internet connection.
- A dedicated target disk with at least 40 GB recommended (100 GB+ preferred for a comfortable desktop).
- The target disk can be completely erased.

## Run

1. Boot the official Arch ISO and connect to the internet.
2. Download or copy `install.sh` onto the live environment. If using another USB partition, mount it first and `cd` to the folder containing the script.
3. Run:

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

   The live ISO logs in as root, so no `sudo` is needed. If you copied the script to a writable folder and permissions are unavailable, run `bash install.sh`.
4. Enter a username, hostname, timezone (for Egypt: `Africa/Cairo`), keyboard layout, and passwords.
5. Carefully inspect the full disk/partition listing. Choose the whole target disk, not a partition.
6. Type the two confirmation phrases exactly. If uncertain, type anything else to cancel.
7. Keep the machine powered and connected to the internet until it completes. Do not interrupt pacstrap or the AUR build.
8. Review the log and warnings, then run `umount -R /mnt` and `reboot` when instructed.

## Starter keybindings

- `Super+Enter`: terminal
- `Super+D`: application launcher
- `Super+E`: file manager
- `Super+Q`: close active window
- `Super+M`: exit Hyprland

## Before using on a primary PC

The safer next milestone is a test run in a VM or on a spare disk. For production use, we should add explicit disk serial confirmation, optional encryption, swap/zram choices, proper Caelestia upstream dotfiles setup, GPU-specific packages, automatic rollback/snapshot configuration, and better recovery handling.
