#!/usr/bin/env bash
# PHI Arch + Hyprland + Caelestia guided installer
# WARNING: selected target disk is repartitioned and erased after explicit confirmation.
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME='PHI Arch Caelestia Installer'
LOG_DIR='/var/log'
LOG_FILE="${LOG_DIR}/phi-arch-caelestia-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RESET='\033[0m'
info(){ printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok(){ printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
die(){ printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }
cleanup(){ if mountpoint -q /mnt; then warn 'Installation stopped. The target may remain mounted at /mnt; rebooting the live ISO is usually simplest.'; fi; }
trap cleanup EXIT
trap 'die "Unexpected failure at line $LINENO. See log: $LOG_FILE"' ERR

[[ $EUID -eq 0 ]] || die 'Run as root from the Arch Linux live ISO: sudo bash install.sh'
[[ -d /run/archiso ]] || warn 'This does not look like the official Arch live ISO. Continuing is risky.'
[[ -d /sys/firmware/efi ]] || die 'UEFI boot is required. Reboot the USB and choose its UEFI boot entry.'

clear || true
cat <<'BANNER'
============================================================
 PHI ARCH INSTALLER — Hyprland + Caelestia Shell
 Guided UEFI/GPT + Btrfs installation
============================================================
This installer ERASES the selected target disk after confirmation.
It does not support dual-boot or preserving existing partitions.
Disconnect backup drives and verify the disk model carefully.
BANNER
printf '\nLog file: %s\n\n' "$LOG_FILE"

read -r -p 'New Linux username (lowercase letters/numbers/_/-): ' USERNAME
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'Invalid username.'
read -r -p 'Computer hostname: ' HOSTNAME
[[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || die 'Invalid hostname.'
read -r -p 'Timezone (e.g. Africa/Cairo): ' TIMEZONE
[[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die 'Timezone not found on live media. Use a valid zoneinfo path, e.g. Africa/Cairo.'
read -r -p 'Keyboard layout [us]: ' KEYMAP
KEYMAP=${KEYMAP:-us}
[[ "$KEYMAP" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Invalid keymap.'
read -r -s -p 'Set user password: ' USERPASS; printf '\n'
read -r -s -p 'Confirm user password: ' USERPASS2; printf '\n'
[[ "$USERPASS" == "$USERPASS2" ]] || die 'Passwords do not match.'
read -r -s -p 'Set root password: ' ROOTPASS; printf '\n'

info 'Checking internet connectivity...'
ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || warn 'Ping failed. Confirm networking and mirror access before proceeding.'
command -v pacman >/dev/null || die 'pacman not found. Boot the official Arch Linux live ISO.'

info 'Available whole disks (USB drives included):'
lsblk -d -o NAME,PATH,SIZE,MODEL,TRAN,TYPE | sed -n '1,30p'
printf '\nDetailed disk and partition inventory:\n'
lsblk -o NAME,PATH,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,TYPE
printf '\nEnter the WHOLE target disk path (examples: /dev/nvme0n1 or /dev/sda).\n'
read -r -p 'Target disk: ' DISK
[[ -b "$DISK" ]] || die 'That path is not a block device.'
[[ "$(lsblk -dn -o TYPE "$DISK")" == 'disk' ]] || die 'Select a whole disk, not a partition.'
[[ "$DISK" != /dev/loop* ]] || die 'Loop devices cannot be installation targets.'

# Refuse target disks with mounted descendants to reduce accidental damage.
mapfile -t MOUNTED < <(lsblk -nrpo NAME,MOUNTPOINTS "$DISK" | awk 'NF>1 && $2!="" {print $1 ":" $2}')
((${#MOUNTED[@]} == 0)) || { printf '%s\n' "${MOUNTED[@]}"; die 'Target disk or one of its partitions is mounted. Unmount it first; do not target the live USB.'; }

printf '\nSelected target:\n'
lsblk -d -o PATH,SIZE,MODEL,TRAN "$DISK"
printf '\nPartitions currently on target:\n'
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DISK"
printf '\n${YELLOW}ALL DATA ON THIS DISK WILL BE DESTROYED.${RESET}\n'
read -r -p "To proceed, type exactly: ERASE $DISK : " CONFIRM
[[ "$CONFIRM" == "ERASE $DISK" ]] || die 'Confirmation did not match. No disk changes were made.'
read -r -p 'Final confirmation: type YES-ERASE-DISK: ' CONFIRM2
[[ "$CONFIRM2" == 'YES-ERASE-DISK' ]] || die 'Final confirmation did not match. No disk changes were made.'

info 'Refreshing Arch package databases...'
pacman -Sy --noconfirm
pacman -S --needed --noconfirm archlinux-keyring btrfs-progs dosfstools gptfdisk git base-devel

# Partitioning is intentionally explicit and occurs only after two confirmations.
info "Wiping partition signatures and creating GPT on $DISK ..."
swapoff -a || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -o "$DISK"
sgdisk -n 1:0:+1GiB -t 1:EF00 -c 1:EFI "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:ARCHROOT "$DISK"
partprobe "$DISK"
sleep 2

if [[ "$DISK" =~ nvme|mmcblk ]]; then EFI_PART="${DISK}p1"; ROOT_PART="${DISK}p2"; else EFI_PART="${DISK}1"; ROOT_PART="${DISK}2"; fi
[[ -b "$EFI_PART" && -b "$ROOT_PART" ]] || die "Could not find created partitions ($EFI_PART, $ROOT_PART). Reboot live media and inspect the disk."

mkfs.fat -F32 -n PHI_EFI "$EFI_PART"
mkfs.btrfs -f -L PHI_ARCH "$ROOT_PART"
mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt
mount -o noatime,compress=zstd:1,subvol=@ "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o noatime "$EFI_PART" /mnt/boot
mount -o noatime,compress=zstd:1,subvol=@home "$ROOT_PART" /mnt/home
mount -o noatime,compress=zstd:1,subvol=@var_log "$ROOT_PART" /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,subvol=@snapshots "$ROOT_PART" /mnt/.snapshots

ARCH=$(uname -m)
CPU_VENDOR=$(grep -m1 -E 'vendor_id' /proc/cpuinfo | awk '{print $3}')
MICROCODE=''
[[ "$CPU_VENDOR" == GenuineIntel ]] && MICROCODE='intel-ucode'
[[ "$CPU_VENDOR" == AuthenticAMD ]] && MICROCODE='amd-ucode'

PACKAGES=(base linux linux-firmware linux-headers btrfs-progs dosfstools efibootmgr grub networkmanager sudo git base-devel nano vim man-db man-pages texinfo curl wget rsync openssh pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol alsa-utils bluez bluez-utils brightnessctl ddcutil lm_sensors power-profiles-daemon xdg-user-dirs xdg-utils xdg-desktop-portal xdg-desktop-portal-hyprland polkit-gnome qt6-wayland qt5-wayland kitty foot thunar gvfs tumbler file-roller firefox wl-clipboard cliphist grim slurp satty swappy imagemagick jq unzip zip p7zip fastfetch btop htop playerctl mpv imv loupe network-manager-applet wofi waybar hyprland hyprpaper hypridle hyprlock hyprpicker xorg-xwayland mesa vulkan-radeon vulkan-icd-loader libva-mesa-driver noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation ttf-cascadia-code-nerd ttf-rubik-vf ttf-material-symbols-variable fish zsh)
[[ -n "$MICROCODE" ]] && PACKAGES+=("$MICROCODE")

info 'Installing the base system and desktop packages. This may take a while...'
pacstrap -K /mnt "${PACKAGES[@]}"
genfstab -U /mnt >> /mnt/etc/fstab

# Use a root-owned temporary config script; credentials are passed via environment and never written into the log.
install -d -m 700 /mnt/root
cat > /mnt/root/phi-configure.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf
printf '%s\n' "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF_HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOF_HOSTS
printf 'root:%s\n' "$ROOTPASS" | chpasswd
useradd -m -G wheel,audio,video,storage,optical,lp -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USERPASS" | chpasswd
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
systemctl enable NetworkManager bluetooth power-profiles-daemon
systemctl enable fstrim.timer

# GRUB for UEFI; no existing EFI partition is reused because this installer intentionally wipes the selected disk.
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=PHI-Arch --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Create a safe, basic Hyprland session and autostart Caelestia Shell.
install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config/hypr" "/home/$USERNAME/.config/caelestia-installer"
cat > "/home/$USERNAME/.config/hypr/hyprland.conf" <<'HYPR'
# PHI Hyprland starter config. Customize after first successful login.
monitor = ,preferred,auto,1
$terminal = kitty
$menu = wofi --show drun
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = waybar
exec-once = hyprpaper
exec-once = caelestia shell -d
input {
  kb_layout = us
  follow_mouse = 1
  touchpad {
    natural_scroll = yes
  }
}
general {
  gaps_in = 5
  gaps_out = 10
  border_size = 2
  layout = dwindle
}
decoration {
  rounding = 10
  blur {
    enabled = yes
    size = 6
    passes = 2
  }
}
animations { enabled = yes }
dwindle {
  pseudotile = yes
  preserve_split = yes
}
$mod = SUPER
bind = $mod, RETURN, exec, $terminal
bind = $mod, D, exec, $menu
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, F, fullscreen
bind = $mod, V, togglefloating
bind = $mod, E, exec, thunar
bind = $mod SHIFT, S, exec, grim -g "$(slurp)" - | satty --filename -
HYPR
cat > "/home/$USERNAME/.config/hypr/hyprpaper.conf" <<'PAPER'
# Set a wallpaper with: hyprctl hyprpaper wallpaper "",/path/to/image
PAPER
cat > "/home/$USERNAME/.bash_profile" <<'PROFILE'
if [[ -z "$WAYLAND_DISPLAY" && "$(tty)" == /dev/tty1 ]]; then
  exec Hyprland
fi
PROFILE
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config" "/home/$USERNAME/.bash_profile"

# Install AUR helper and stable Caelestia Shell as an unprivileged build user.
# AUR package recipes are community-maintained; inspect them if you need a fully audited supply chain.
runuser -u "$USERNAME" -- bash -lc '
  set -e
  cd /tmp
  git clone https://aur.archlinux.org/yay.git yay-build
  cd yay-build
  makepkg -si --noconfirm
  yay -S --needed --noconfirm caelestia-shell brave-bin hyprmod
'

# Set Brave as the default browser for HTTP/HTTPS links and HTML documents.
# brave-bin normally installs brave-browser.desktop; check that the desktop entry exists first.
if [[ -f /usr/share/applications/brave-browser.desktop ]]; then
  runuser -u "$USERNAME" -- xdg-mime default brave-browser.desktop x-scheme-handler/http
  runuser -u "$USERNAME" -- xdg-mime default brave-browser.desktop x-scheme-handler/https
  runuser -u "$USERNAME" -- xdg-mime default brave-browser.desktop text/html
  runuser -u "$USERNAME" -- xdg-settings set default-web-browser brave-browser.desktop || true
else
  echo 'WARNING: Brave desktop entry was not found; set the default browser manually after login.'
fi

# Ensure desktop essentials are present; do not install a third-party full dotfiles bundle over user configs.
install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config"
chown "$USERNAME:$USERNAME" "/home/$USERNAME"
printf '\nPHI Arch installation complete.\n' > /etc/issue
CHROOT
chmod 700 /mnt/root/phi-configure.sh

info 'Configuring the installed system...'
arch-chroot /mnt env \
  USERNAME="$USERNAME" HOSTNAME="$HOSTNAME" TIMEZONE="$TIMEZONE" KEYMAP="$KEYMAP" \
  USERPASS="$USERPASS" ROOTPASS="$ROOTPASS" bash /root/phi-configure.sh
rm -f /mnt/root/phi-configure.sh
unset USERPASS USERPASS2 ROOTPASS

cat > /mnt/etc/skel/README-PHI-ARCH.txt <<'README'
PHI Arch + Hyprland + Caelestia

Login on tty1 and Hyprland should start from ~/.bash_profile.
Default starter keybinds:
  Super+Enter  terminal
  Super+D      application launcher
  Super+E      file manager
  Super+Q      close active window
  Super+M      exit Hyprland

Caelestia shell autostarts from Hyprland. If it fails, inspect the terminal/logs and run:
  caelestia shell -d

This is a starter setup, not a full upstream Caelestia dotfiles configuration.
README

ok 'Installation files were configured.'
cat <<EOF

============================================================
 INSTALLATION FINISHED
============================================================
Target: $DISK
User:   $USERNAME
Log:    $LOG_FILE

Review any warnings above. Then reboot and remove the USB drive:
  umount -R /mnt
  reboot

If boot entry creation fails, firmware boot menu may require selecting
PHI-Arch manually. Keep the Arch USB until first successful login.
============================================================
EOF
trap - EXIT
