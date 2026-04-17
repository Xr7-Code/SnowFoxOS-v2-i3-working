#!/bin/bash
# ============================================================
#  SnowFoxOS v2.0 — Installer
#  Basis: Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#  Ausführen: sudo ./install.sh
# ============================================================

set -e

PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${PURPLE}${BOLD}[SnowFox]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[  OK  ]${RESET} $1"; }
warn()    { echo -e "${ORANGE}${BOLD}[ WARN ]${RESET} $1"; }
error()   { echo -e "${RED}${BOLD}[FEHLER]${RESET} $1"; exit 1; }
step()    { echo -e "\n${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}";
            echo -e "${PURPLE}${BOLD}  $1${RESET}";
            echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }

if [[ $EUID -ne 0 ]]; then
    error "Bitte mit sudo ausführen: sudo ./install.sh"
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Benutzername: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ! -d "$TARGET_HOME" ]] && error "Home $TARGET_HOME nicht gefunden"

info "Installiere für: ${BOLD}$TARGET_USER${RESET}"
sleep 1

# ============================================================
# SCHRITT 1 — System & Repositories
# ============================================================
step "1/10 — System aktualisieren"

cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF

dpkg --add-architecture i386
apt-get update -qq
apt-get upgrade -y
apt-get install -y \
    curl wget git unzip \
    build-essential \
    ca-certificates \
    pciutils usbutils \
    htop btop neofetch \
    bash-completion \
    xdg-utils \
    xdg-user-dirs \
    rfkill \
    imagemagick \
    bc \
    xorg \
    xinit \
    x11-utils \
    x11-xserver-utils \
    xclip \
    xdotool

sudo -u "$TARGET_USER" xdg-user-dirs-update

# Fritz USB AC 860 Treiber (mt76x2u)
info "Prüfe Fritz USB AC 860 Treiber..."
apt-get install -y firmware-misc-nonfree linux-headers-$(uname -r) 2>/dev/null || true
if lsusb 2>/dev/null | grep -qi "fritz\|0x0bda\|2357"; then
    modprobe mt76x2u 2>/dev/null && \
        success "Fritz USB AC 860 Treiber geladen (mt76x2u)" || \
        warn "Fritz USB AC 860 Treiber nicht gefunden — nach Reboot prüfen"
fi

success "System aktualisiert"

# ============================================================
# SCHRITT 2 — GPU-Erkennung & Treiber
# ============================================================
step "2/10 — GPU-Erkennung & Treiber"

GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false
IS_HYBRID=false

echo "$GPU_INFO" | grep -qi "nvidia" && HAS_NVIDIA=true && info "Nvidia GPU gefunden"
echo "$GPU_INFO" | grep -qi "amd\|radeon\|advanced micro" && HAS_AMD=true && info "AMD GPU gefunden"
echo "$GPU_INFO" | grep -qi "intel" && HAS_INTEL=true && info "Intel GPU gefunden"
[[ "$HAS_NVIDIA" = true && ( "$HAS_AMD" = true || "$HAS_INTEL" = true ) ]] && IS_HYBRID=true

if $HAS_AMD || $HAS_INTEL; then
    apt-get install -y \
        libgl1-mesa-dri libgl1-mesa-dri:i386 \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        mesa-va-drivers mesa-vdpau-drivers 2>/dev/null || true
    $HAS_AMD && apt-get install -y firmware-amd-graphics 2>/dev/null || true
    $HAS_INTEL && apt-get install -y intel-media-va-driver xserver-xorg-video-intel 2>/dev/null || true
    success "Mesa/AMD/Intel Treiber installiert"
fi

if $HAS_NVIDIA; then
    apt-get install -y linux-headers-$(uname -r) 2>/dev/null || true
    apt-get install -y \
        nvidia-driver \
        nvidia-kernel-dkms \
        firmware-misc-nonfree \
        libgbm1 \
        nvidia-vulkan-icd \
        nvidia-vulkan-icd:i386 \
        nvidia-settings 2>/dev/null || true

    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
install nouveau /bin/false
EOF
    update-initramfs -u -k all 2>/dev/null || true
    success "Nvidia Treiber installiert"
fi

if $IS_HYBRID; then
    apt-get install -y python3 python3-pip
    pip3 install envycontrol --break-system-packages 2>/dev/null || true
    if command -v envycontrol &>/dev/null; then
        envycontrol -s nvidia 2>/dev/null && success "envycontrol: Nvidia-Modus aktiviert" || true
        warn "Hybrid-GPU: Alle Monitore an die Nvidia-Karte anschließen!"
    fi
fi

if ! $HAS_NVIDIA && ! $HAS_AMD && ! $HAS_INTEL; then
    apt-get install -y libgl1-mesa-dri libgl1-mesa-dri:i386 mesa-vulkan-drivers 2>/dev/null || true
fi

success "GPU-Treiber eingerichtet"

# ============================================================
# SCHRITT 3 — i3 Desktop
# ============================================================
step "3/10 — i3 + Polybar + Rofi + Dunst + i3lock"

apt-get install -y \
    i3 \
    i3status \
    i3lock \
    polybar \
    rofi \
    dunst \
    libnotify-bin \
    feh \
    redshift \
    scrot \
    xautolock \
    brightnessctl \
    playerctl \
    network-manager \
    network-manager-gnome \
    nm-tray \
    bluez \
    blueman \
    fonts-inter \
    fonts-noto \
    fonts-noto-color-emoji \
    papirus-icon-theme \
    lxappearance \
    picom \
    xss-lock \
    xserver-xorg-input-libinput

# Touchpad Konfiguration
mkdir -p /etc/X11/xorg.conf.d
cp "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
success "Touchpad konfiguriert"

success "i3 Desktop installiert"

# i3 startet automatisch von TTY1
BASH_PROFILE="$TARGET_HOME/.bash_profile"
if ! grep -q "startx" "$BASH_PROFILE" 2>/dev/null; then
    echo '' >> "$BASH_PROFILE"
    echo '# SnowFoxOS — i3 automatisch starten' >> "$BASH_PROFILE"
    echo '[ "$(tty)" = "/dev/tty1" ] && exec startx' >> "$BASH_PROFILE"
fi

# xinitrc
cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
# SnowFoxOS xinitrc
exec i3
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"

success "i3 Autostart eingerichtet"

# ============================================================
# SCHRITT 4 — Audio (PipeWire)
# ============================================================
step "4/10 — Audio (PipeWire)"

apt-get install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    pavucontrol \
    pulseaudio-utils

apt-get remove --purge -y pulseaudio 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

success "PipeWire installiert"

# ============================================================
# SCHRITT 5 — Terminal & Apps
# ============================================================
step "5/10 — Terminal & Standard-Apps"

apt-get install -y \
    kitty \
    mc \
    mousepad \
    ristretto \
    file-roller \
    mpv \
    ffmpeg \
    gnupg

# Dateimanager Auswahl
echo ""
echo -e "${PURPLE}${BOLD}  Welchen Dateimanager möchtest du installieren?${RESET}"
echo -e "  1) Thunar  (grafisch, empfohlen)"
echo -e "  2) MC      (Terminal, Midnight Commander)"
echo -e "  3) Beide"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-3]: "${RESET})" FM_CHOICE
case "$FM_CHOICE" in
    1)
        apt-get install -y thunar thunar-archive-plugin thunar-volman gvfs gvfs-backends
        success "Thunar installiert"
        ;;
    2)
        success "MC bereits installiert"
        ;;
    3)
        apt-get install -y thunar thunar-archive-plugin thunar-volman gvfs gvfs-backends
        success "Thunar + MC installiert"
        ;;
    *)
        apt-get install -y thunar thunar-archive-plugin thunar-volman gvfs gvfs-backends
        success "Thunar installiert (Standard)"
        ;;
esac

# VSCodium
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] VSCodium installieren? (Code Editor ohne Telemetrie) [j/n]: "${RESET})" INSTALL_VSCODIUM
if [[ "$INSTALL_VSCODIUM" == "j" || "$INSTALL_VSCODIUM" == "J" ]]; then
    set +e
    curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
        | gpg --dearmor \
        | tee /usr/share/keyrings/vscodium-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" \
        | tee /etc/apt/sources.list.d/vscodium.list
    apt-get update -qq
    apt-get install -y codium && success "VSCodium installiert" || warn "VSCodium fehlgeschlagen — manuell: apt install codium"
    set -e
else
    info "VSCodium übersprungen"
fi

# OnlyOffice Desktop
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] OnlyOffice Desktop installieren? (Office Suite) [j/n]: "${RESET})" INSTALL_ONLYOFFICE
if [[ "$INSTALL_ONLYOFFICE" == "j" || "$INSTALL_ONLYOFFICE" == "J" ]]; then
    set +e
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
        | gpg --dearmor \
        | tee /usr/share/keyrings/onlyoffice-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/onlyoffice-archive-keyring.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
        | tee /etc/apt/sources.list.d/onlyoffice.list
    apt-get update -qq
    apt-get install -y onlyoffice-desktopeditors && success "OnlyOffice installiert" || warn "OnlyOffice fehlgeschlagen — manuell installierbar"
    set -e
else
    info "OnlyOffice übersprungen"
fi

# yt-dlp von GitHub
curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp
success "yt-dlp installiert"

success "Terminal & Apps installiert"

# ============================================================
# SCHRITT 6 — Browser
# ============================================================
step "6/10 — Browser"

echo ""
echo -e "${PURPLE}${BOLD}  Welchen Browser möchtest du installieren?${RESET}"
echo -e "  ${CYAN:-}1${RESET}) Chromium  (empfohlen — leicht, kein Tracking)"
echo -e "  ${CYAN:-}2${RESET}) Falkon    (sehr leicht, Qt-basiert)"
echo -e "  ${CYAN:-}3${RESET}) Brave     (mehr Privacy-Features)"
echo -e "  ${CYAN:-}4${RESET}) Keinen    (später selbst installieren)"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-4]: "${RESET})" BROWSER_CHOICE

BROWSER_NAME="keiner"
case "$BROWSER_CHOICE" in
    1)
        apt-get install -y chromium
        BROWSER_NAME="Chromium"
        success "Chromium installiert"
        ;;
    2)
        apt-get install -y falkon
        BROWSER_NAME="Falkon"
        success "Falkon installiert"
        ;;
    3)
        curl -fsS https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
            | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
            | tee /etc/apt/sources.list.d/brave-browser.list
        apt-get update -qq
        apt-get install -y brave-browser
        BROWSER_NAME="Brave"
        success "Brave installiert"
        ;;
    *)
        warn "Kein Browser installiert"
        ;;
esac

apt-get remove --purge -y firefox-esr 2>/dev/null || true

# ============================================================
# SCHRITT 7 — Steam
# ============================================================
step "7/10 — Steam"

read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] Steam installieren? [j/n]: "${RESET})" INSTALL_STEAM
if [[ "$INSTALL_STEAM" == "j" || "$INSTALL_STEAM" == "J" ]]; then
    apt-get install -y \
        steam \
        steam-devices \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools \
        libgl1-mesa-dri:i386 \
        mesa-vulkan-drivers:i386 2>/dev/null || warn "Steam teilweise fehlgeschlagen"

    cat > /etc/profile.d/snowfox-steam.sh << 'EOF'
export STEAM_RUNTIME=1
EOF
    chmod +x /etc/profile.d/snowfox-steam.sh
    success "Steam installiert — Proton für Windows-Spiele verfügbar"
else
    info "Steam übersprungen"
fi

# ============================================================
# SCHRITT 8 — Performance & Akku
# ============================================================
step "8/10 — Performance & Akku"

apt-get install -y \
    zram-tools \
    tlp \
    tlp-rdw \
    preload \
    earlyoom

cat > /etc/default/zramswap << 'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

systemctl enable zramswap tlp preload earlyoom

# earlyoom — killt Prozesse bei wenig RAM bevor System einfriert
cat > /etc/default/earlyoom << 'EOF'
EARLYOOM_ARGS="-r 60 -m 5 -s 5"
EOF

cat > /etc/sysctl.d/99-snowfox.conf << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

# /tmp im RAM
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

info "Unnötige Dienste deaktivieren..."
for svc in avahi-daemon cups cups-browsed ModemManager e2scrub_reap bluetooth; do
    systemctl disable "$svc" 2>/dev/null && info "  Deaktiviert: $svc" || true
done

sudo -u "$TARGET_USER" systemctl --user mask \
    at-spi-dbus-bus.service \
    gnome-keyring-daemon.service \
    gnome-keyring-daemon.socket \
    obex.service 2>/dev/null || true

# xdg-desktop-portal-gtk deaktivieren — verursacht 30s Delay auf i3
# Stattdessen eigene Service-Override Datei
mkdir -p "/home/$TARGET_USER/.config/systemd/user"
cat > "/home/$TARGET_USER/.config/systemd/user/xdg-desktop-portal-gtk.service" << 'EOF'
[Unit]
Description=Disable GTK portal (i3 fix)
[Service]
ExecStart=/bin/false
EOF
chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/systemd"

# Fonts für Icons
apt-get install -y fonts-noto fonts-noto-color-emoji fonts-font-awesome 2>/dev/null || true

systemctl disable ollama 2>/dev/null || true

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/snowfox.conf << 'EOF'
[device]
wifi.scan-rand-mac-address=no

[main]
plugins=ifupdown,keyfile
connectivity-check-enabled=false

[ifupdown]
managed=true
EOF

systemctl enable NetworkManager
success "Performance & Akku optimiert"

# ============================================================
# SCHRITT 9 — GRUB & Plymouth
# ============================================================
step "9/10 — GRUB & Plymouth"

# GRUB Timeout kürzen
if [[ -f /etc/default/grub ]]; then
    sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    update-grub 2>/dev/null || true
    success "GRUB Timeout auf 2s gesetzt"
fi

# Plymouth
apt-get install -y plymouth plymouth-themes 2>/dev/null || true

# SnowFox Plymouth Theme
PLYMOUTH_DIR="/usr/share/plymouth/themes/snowfox"
mkdir -p "$PLYMOUTH_DIR"

cat > "$PLYMOUTH_DIR/snowfox.plymouth" << 'EOF'
[Plymouth Theme]
Name=SnowFox
Description=SnowFoxOS Boot Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/snowfox
ScriptFile=/usr/share/plymouth/themes/snowfox/snowfox.script
EOF

cat > "$PLYMOUTH_DIR/snowfox.script" << 'EOF'
wallpaper_image = Image("background.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
wallpaper_sprite = Sprite(wallpaper_image);
wallpaper_sprite.SetX(screen_width / 2 - wallpaper_image.GetWidth() / 2);
wallpaper_sprite.SetY(screen_height / 2 - wallpaper_image.GetHeight() / 2);

logo_image = Image("logo.png");
logo_sprite = Sprite(logo_image);
logo_sprite.SetX(screen_width / 2 - logo_image.GetWidth() / 2);
logo_sprite.SetY(screen_height / 2 - logo_image.GetHeight() / 2);
EOF

# SnowFox Logo als Plymouth Logo
if [[ -f "$SCRIPT_DIR/assets/fuchs.png" ]]; then
    convert "$SCRIPT_DIR/assets/fuchs.png" -resize 200x200 "$PLYMOUTH_DIR/logo.png" 2>/dev/null || true
fi

# Schwarzer Hintergrund
convert -size 1920x1080 xc:#0f0f0f "$PLYMOUTH_DIR/background.png" 2>/dev/null || true

plymouth-set-default-theme snowfox 2>/dev/null || true
update-initramfs -u 2>/dev/null || true
success "Plymouth Theme installiert"

# ============================================================
# SCHRITT 10 — Konfiguration
# ============================================================
step "10/10 — Konfiguration & Darkmode"

CONFIG_DIR="$TARGET_HOME/.config"
mkdir -p \
    "$CONFIG_DIR/i3" \
    "$CONFIG_DIR/polybar" \
    "$CONFIG_DIR/rofi" \
    "$CONFIG_DIR/dunst" \
    "$CONFIG_DIR/kitty" \
    "$CONFIG_DIR/mpv" \
    "$CONFIG_DIR/gtk-3.0" \
    "$CONFIG_DIR/gtk-4.0" \
    "$TARGET_HOME/Pictures/wallpapers"

# i3 Config
cp "$SCRIPT_DIR/configs/i3/config"      "$CONFIG_DIR/i3/config"

# Polybar
cp "$SCRIPT_DIR/configs/polybar/config.ini" "$CONFIG_DIR/polybar/config.ini"
cp "$SCRIPT_DIR/configs/polybar/launch.sh"  "$CONFIG_DIR/polybar/launch.sh"
chmod +x "$CONFIG_DIR/polybar/launch.sh"

# Fox Logo für Polybar
if [[ -f "$SCRIPT_DIR/assets/fuchs.png" ]]; then
    convert "$SCRIPT_DIR/assets/fuchs.png" -resize 24x24 "$CONFIG_DIR/polybar/fox.png" 2>/dev/null && \
        info "Fox Logo für Polybar erstellt" || \
        warn "Fox Logo konnte nicht konvertiert werden"
fi

# Rofi
cp "$SCRIPT_DIR/configs/rofi/config.rasi" "$CONFIG_DIR/rofi/config.rasi"

# Dunst
cp "$SCRIPT_DIR/configs/dunst/dunstrc" "$CONFIG_DIR/dunst/dunstrc"

# Scripts
cp "$SCRIPT_DIR/configs/snowfox-network.sh" "$CONFIG_DIR/snowfox-network.sh"
cp "$SCRIPT_DIR/configs/snowfox-display.sh" "$CONFIG_DIR/snowfox-display.sh"
cp "$SCRIPT_DIR/configs/snowfox-lock.sh"    "$CONFIG_DIR/snowfox-lock.sh"
cp "$SCRIPT_DIR/configs/powermenu.sh"       "$CONFIG_DIR/powermenu.sh"
chmod +x "$CONFIG_DIR/snowfox-network.sh" \
         "$CONFIG_DIR/snowfox-display.sh" \
         "$CONFIG_DIR/snowfox-lock.sh" \
         "$CONFIG_DIR/powermenu.sh"

# Touchpad (falls nicht schon in Schritt 3 kopiert)
if [[ -f "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" ]]; then
    mkdir -p /etc/X11/xorg.conf.d
    cp "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
fi

# Kitty
cat > "$CONFIG_DIR/kitty/kitty.conf" << 'EOF'
font_family       Noto Mono
font_size         11.0
cursor            #9B59B6
cursor_text_color #0f0f0f
background        #0f0f0f
foreground        #e8e8e8
color0   #1a1a1a
color1   #e05555
color2   #5faf5f
color3   #E67E22
color4   #5f87af
color5   #9B59B6
color6   #5fafaf
color7   #bcbcbc
color8   #3a3a3a
color9   #ff6e6e
color10  #87d787
color11  #ffd787
color12  #87afd7
color13  #c397d8
color14  #87d7d7
color15  #e8e8e8
window_padding_width 8
hide_window_decorations yes
confirm_os_window_close 0
EOF

# mpv
cat > "$CONFIG_DIR/mpv/mpv.conf" << 'EOF'
vo=gpu
hwdec=auto
EOF

# GTK Darkmode
cat > "$CONFIG_DIR/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-enable-animations=0
EOF

cat > "$CONFIG_DIR/gtk-4.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
EOF

# Darkmode für Chromium/Brave über Flags
mkdir -p "$CONFIG_DIR"
if [[ -f "$CONFIG_DIR/chromium-flags.conf" ]] || command -v chromium &>/dev/null; then
    echo "--force-dark-mode
--enable-features=WebUIDarkMode" >> "$CONFIG_DIR/chromium-flags.conf" 2>/dev/null || true
fi
if command -v brave-browser &>/dev/null; then
    echo "--force-dark-mode
--enable-features=WebUIDarkMode" >> "$TARGET_HOME/.config/brave-flags.conf" 2>/dev/null || true
fi

# xdg-desktop-portal für X11/i3 — gtk Portal installieren damit Thunar nicht hängt
apt-get install -y xdg-desktop-portal xdg-desktop-portal-gtk 2>/dev/null || true

# Akku automatisch erkennen (BAT0 oder BAT1)
BAT_NAME="BAT0"
for bat in /sys/class/power_supply/BAT*; do
    [[ -d "$bat" ]] && BAT_NAME=$(basename "$bat") && break
done
info "Akku erkannt: $BAT_NAME"
sed -i "s/^battery = BAT.*/battery = $BAT_NAME/" "$CONFIG_DIR/polybar/config.ini" 2>/dev/null || true

# Power-Button → Power-Menü
mkdir -p /etc/acpi/events
cat > /etc/acpi/events/powerbtn << 'EOF'
event=button/power
action=/etc/acpi/powerbtn.sh
EOF
cat > /etc/acpi/powerbtn.sh << 'ACPI'
#!/bin/bash
USER_NAME=$(logname 2>/dev/null || who | awk '{print $1}' | head -1)
DISPLAY=:0 XAUTHORITY="/home/$USER_NAME/.Xauthority" \
    su "$USER_NAME" -c "~/.config/powermenu.sh"
ACPI
chmod +x /etc/acpi/powerbtn.sh
apt-get install -y acpid 2>/dev/null || true
systemctl enable acpid 2>/dev/null || true
success "Power-Button konfiguriert"

# Wallpaper
if [ -d "$SCRIPT_DIR/wallpapers" ] && [ "$(ls -A "$SCRIPT_DIR/wallpapers" 2>/dev/null)" ]; then
    cp "$SCRIPT_DIR/wallpapers"/* "$TARGET_HOME/Pictures/wallpapers/"
    success "Wallpapers kopiert"
fi

# SnowFox Logo
ASSET="$SCRIPT_DIR/assets/fuchs.png"
if [[ -f "$ASSET" ]]; then
    for SIZE in 16 24 32 48 64 128 256; do
        ICON_DIR="/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps"
        mkdir -p "$ICON_DIR"
        convert "$ASSET" -resize "${SIZE}x${SIZE}" "$ICON_DIR/snowfox.png" 2>/dev/null || true
    done
    gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true
fi

# gnome-keyring aus PAM
sed -i 's/^password.*pam_gnome_keyring.so/# &/' /etc/pam.d/common-password 2>/dev/null || true

# snowfox CLI
cp "$SCRIPT_DIR/snowfox" /usr/local/bin/snowfox
chmod +x /usr/local/bin/snowfox
success "snowfox CLI installiert"

# snowfox Greeting
cp "$SCRIPT_DIR/snowfox-greeting.sh" /usr/local/bin/snowfox-greeting
chmod +x /usr/local/bin/snowfox-greeting
BASHRC="$TARGET_HOME/.bashrc"
if ! grep -q "snowfox-greeting" "$BASHRC" 2>/dev/null; then
    echo '' >> "$BASHRC"
    echo '# SnowFoxOS Greeting' >> "$BASHRC"
    echo '[[ -x /usr/local/bin/snowfox-greeting ]] && snowfox-greeting' >> "$BASHRC"
fi

# Ollama
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] Ollama + llama3.2 installieren? (Offline-KI, ca. 2GB) [j/n]: "${RESET})" INSTALL_OLLAMA
if [[ "$INSTALL_OLLAMA" == "j" || "$INSTALL_OLLAMA" == "J" ]]; then
    curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null && success "Ollama installiert" || warn "Ollama fehlgeschlagen"
    if command -v ollama &>/dev/null; then
        sudo -u "$TARGET_USER" ollama pull llama3.2 2>/dev/null && success "llama3.2 bereit" || warn "Download fehlgeschlagen"
    fi
else
    info "Ollama übersprungen"
fi

# Berechtigungen
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/Pictures"

# ============================================================
# Fertig!
# ============================================================
echo ""
echo -e "${PURPLE}${BOLD}"
echo "  ███████╗███╗  ██╗ ██████╗ ██╗    ██╗███████╗ ██████╗ ██╗  ██╗"
echo "  ██╔════╝████╗ ██║██╔═══██╗██║    ██║██╔════╝██╔═══██╗╚██╗██╔╝"
echo "  ███████╗██╔██╗██║██║   ██║██║ █╗ ██║█████╗  ██║   ██║ ╚███╔╝ "
echo "  ╚════██║██║╚████║██║   ██║██║███╗██║██╔══╝  ██║   ██║ ██╔██╗ "
echo "  ███████║██║ ╚███║╚██████╔╝╚███╔███╔╝██║     ╚██████╔╝██╔╝╚██╗"
echo "  ╚══════╝╚═╝  ╚══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"
echo -e "${GREEN}${BOLD}  SnowFoxOS v2.0 erfolgreich installiert!${RESET}"
echo ""
echo -e "${GRAY}  Benutzer:   ${BOLD}$TARGET_USER${RESET}"
echo -e "${GRAY}  Desktop:    ${BOLD}i3 + Polybar${RESET}"
echo -e "${GRAY}  Browser:    ${BOLD}$BROWSER_NAME${RESET}"
echo -e "${GRAY}  Audio:      ${BOLD}PipeWire${RESET}"
echo -e "${GRAY}  Darkmode:   ${BOLD}GTK3 + GTK4${RESET}"
echo -e "${GRAY}  CLI:        ${BOLD}snowfox${RESET}"
echo -e "${GRAY}  GPU:        ${BOLD}$(
    $IS_HYBRID && echo "Hybrid → Nvidia-Modus" || \
    ( $HAS_NVIDIA && echo "Nvidia" ) || \
    ( $HAS_AMD && echo "AMD" ) || \
    ( $HAS_INTEL && echo "Intel" ) || \
    echo "Standard Mesa"
)${RESET}"
echo -e "${GRAY}  zram:       ${BOLD}aktiv (lz4, 50%)${RESET}"
echo -e "${GRAY}  tlp:        ${BOLD}aktiv${RESET}"
echo -e "${GRAY}  preload:    ${BOLD}aktiv${RESET}"
echo -e "${GRAY}  earlyoom:   ${BOLD}aktiv${RESET}"
echo -e "${GRAY}  Login:      ${BOLD}TTY1 → Passwort → i3${RESET}"
echo ""
echo -e "${ORANGE}${BOLD}  → Neu starten: sudo reboot${RESET}"
echo ""
