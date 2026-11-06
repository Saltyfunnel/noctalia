#!/usr/bin/env bash
# install-umbriel-clean.sh
#
# Fresh minimal Arch install -> Umbriel compositor + Noctalia v5 desktop shell (with Spicetify).
# Umbriel is Noctalia's own Wayland compositor (wlroots + SceneFX). It is young (0.1.x),
# so expect rough edges. For a Hyprland setup use install-noctalia-clean.sh instead.
# File manager: Thunar.

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root." >&2
    exit 1
fi

BUILD_DIR="$HOME/.cache/noctalia-install"
mkdir -p "$BUILD_DIR"

CONFIRM="--noconfirm"
[[ "${REVIEW:-0}" == "1" ]] && CONFIRM=""

echo "==> pacman.conf tweaks (Color, ParallelDownloads, ILoveCandy, multilib for Steam)"
sudo sed -i 's/^#Color/Color/; s/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || sudo sed -i '/^\[options\]/a ILoveCandy' /etc/pacman.conf
sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf

echo "==> Full system update"
sudo pacman -Syu --noconfirm

echo "==> Base build tools"
sudo pacman -S --needed --noconfirm base-devel git go pciutils

if ! command -v yay &>/dev/null; then
    echo "==> Bootstrapping yay from source"
    rm -rf "$BUILD_DIR/yay"
    git clone --depth=1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay"
    (cd "$BUILD_DIR/yay" && makepkg -si --noconfirm)
fi

install_pkg() {
    yay -S --needed $CONFIRM "$@"
}

# --- 1. GPU detection ---
detect_gpu() {
    local info
    info="$(lspci -nn | grep -Ei 'vga|3d|display' || true)"
    if grep -qi 'nvidia' <<<"$info"; then echo nvidia
    elif grep -Eqi 'amd|ati|radeon' <<<"$info"; then echo amd
    elif grep -qi 'intel' <<<"$info"; then echo intel
    else echo none
    fi
}

GPU="${GPU:-$(detect_gpu)}"
echo "==> GPU: $GPU"

GPU_PKGS=(mesa)
case "$GPU" in
    amd)    GPU_PKGS+=(vulkan-radeon lib32-mesa lib32-vulkan-radeon) ;;
    nvidia) GPU_PKGS+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver linux-headers) ;;
    intel)  GPU_PKGS+=(vulkan-intel lib32-mesa lib32-vulkan-intel intel-media-driver) ;;
    none)   echo "    No GPU matched, installing mesa only." ;;
esac

# --- 2. Umbriel + Portals + Kitty ---
# NOTE: the AUR package "umbriel" is a placeholder. The real one is umbriel-git.
# xwayland-satellite provides X11 app support (Steam needs it).
# xdg-desktop-portal-umbriel-git was a placeholder when this was written, so
# portal-wlr is used for screen capture (untested with Umbriel).
echo "==> Umbriel, portals, terminal (Kitty), graphics"
install_pkg umbriel-git xwayland-satellite \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr \
    "${GPU_PKGS[@]}" \
    kitty \
    ttf-jetbrains-mono-nerd

# --- 3. Core Shell Tools & Utilities ---
echo "==> Core apps and system utilities"
install_pkg fish eza zoxide direnv \
    fastfetch \
    btop \
    ffmpeg 7zip fd fzf imagemagick \
    thunar thunar-archive-plugin thunar-volman gvfs tumbler ffmpegthumbnailer file-roller \
    udiskie udisks2 \
    starship \
    adw-gtk-theme papirus-icon-theme \
    qt6ct nwg-look \
    gnome-keyring polkit-gnome \
    networkmanager \
    bluez bluez-utils \
    pipewire pipewire-pulse pipewire-audio pipewire-alsa pipewire-jack wireplumber pavucontrol \
    wl-clipboard cliphist \
    noto-fonts noto-fonts-cjk noto-fonts-emoji \
    curl trash-cli jq lazygit bat ripgrep xdg-user-dirs libnotify grim slurp

echo "==> Apps"
install_pkg mpv imv qbittorrent libreoffice-fresh zed \
    steam gnome-disk-utility ntfs-3g dosfstools \
    localsend-bin

echo "==> Login manager"
install_pkg sddm xorg-server

# --- 4. Noctalia v5 ---
# noctalia-git pulls in its own runtime deps and lists the optional ones.
echo "==> Noctalia"
install_pkg noctalia-git \
    brightnessctl ddcutil lm_sensors power-profiles-daemon \
    swappy

# --- 5. Config ---
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Umbriel runs as a user service and imports variables from environment.d,
# so the Qt theme platform goes here instead of in the compositor config.
mkdir -p "$XDG_CONFIG_HOME/environment.d"
if [[ ! -f "$XDG_CONFIG_HOME/environment.d/qt.conf" ]]; then
    echo 'QT_QPA_PLATFORMTHEME=qt6ct' > "$XDG_CONFIG_HOME/environment.d/qt.conf"
fi

# Starter Umbriel config. Only written if you don't have one.
# Once this file exists, [keybinds] is the COMPLETE set (defaults only load
# when there is no config), so extend it by hand afterwards.
mkdir -p "$XDG_CONFIG_HOME/umbriel"
# Re-running on an existing install? FORCE_CONFIG=1 backs up the old config and rewrites it.
if [[ "${FORCE_CONFIG:-0}" == "1" && -f "$XDG_CONFIG_HOME/umbriel/config.toml" ]]; then
    mv "$XDG_CONFIG_HOME/umbriel/config.toml" "$XDG_CONFIG_HOME/umbriel/config.toml.bak"
    echo "    Backed up old Umbriel config to config.toml.bak"
fi
if [[ ! -f "$XDG_CONFIG_HOME/umbriel/config.toml" ]]; then
    cat > "$XDG_CONFIG_HOME/umbriel/config.toml" <<'EOF'
[general]
autostart = [
    "noctalia",
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
    "udiskie",
]

[appearance]
prefer_no_csd = true
border_width = 2
corner_radius = 10

[appearance.blur]
enabled = true
optimized = true
passes = 3
radius = 3
noise = 0.02
brightness = 0.9
contrast = 0.9
saturation = 1.1

# Float Noctalia's settings window
[[window_rule]]
match.app_id = "^dev.noctalia.Noctalia$"
default_floating = true
default_size = [1020, 900]

# Blur for Noctalia's bar, panels, notifications, dock and OSD
[[layer_rule]]
match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"
blur = true
blur_ignore_alpha = 0.5
blur_optimized = false

[keybinds]
# Apps
"Mod" = "spawn noctalia msg panel-toggle launcher"
"Mod+Space" = "spawn noctalia msg panel-toggle launcher"
"Mod+Return" = { action = "spawn kitty", repeat = false }
"Mod+E" = "spawn thunar"
"Mod+B" = "spawn zen-browser"
"Mod+C" = "spawn zeditor"
"Mod+S" = "spawn spotify"
"Mod+V" = "spawn noctalia msg panel-toggle clipboard"
"Mod+W" = "spawn noctalia msg panel-toggle wallpaper"
"Mod+P" = "spawn noctalia msg screenshot-region"

# Session / windows
"Mod+Q" = { action = "window-close", repeat = false }
"Mod+Shift+Q" = { action = "window-kill", repeat = false }
"Mod+Escape" = "spawn noctalia msg panel-toggle session"
"Mod+Shift+Escape" = { action = "shortcuts-inhibit-toggle", allow_when_inhibited = true, repeat = false }
"Mod+Ctrl+Escape" = "session-quit"
"Mod+F" = "window-toggle-fullscreen"
"Mod+T" = "window-toggle-floating"
"Mod+Shift+P" = "window-toggle-pinned"
"Mod+Tab" = "window-focus-last"
"Alt+Tab" = "window-focus-last"

# Focus
"Mod+H" = "window-focus-left"
"Mod+L" = "window-focus-right"
"Mod+J" = "window-focus-down"
"Mod+K" = "window-focus-up"
"Mod+Left" = "window-focus-left"
"Mod+Right" = "window-focus-right"
"Mod+Down" = "window-focus-down"
"Mod+Up" = "window-focus-up"

# Move
"Mod+Shift+H" = "window-move-left"
"Mod+Shift+L" = "window-move-right"
"Mod+Shift+J" = "window-move-down"
"Mod+Shift+K" = "window-move-up"
"Mod+Shift+Left" = "column-move-left"
"Mod+Shift+Right" = "column-move-right"
"Mod+Comma" = "window-consume-left"
"Mod+Period" = "window-consume-right"

# Size
"Mod+R" = "window-cycle-primary-extent"
"Mod+Shift+R" = "window-cycle-primary-extent-back"
"Mod+Minus" = "window-modify-primary-extent -0.02"
"Mod+Equal" = "window-modify-primary-extent +0.02"

# Overview / workspaces
"Mod+O" = { action = "overview-toggle", repeat = false }
"Mod+I" = { action = "overview-toggle", repeat = false }
"Mod+1" = "workspace-switch 1"
"Mod+2" = "workspace-switch 2"
"Mod+3" = "workspace-switch 3"
"Mod+4" = "workspace-switch 4"
"Mod+5" = "workspace-switch 5"
"Mod+6" = "workspace-switch 6"
"Mod+7" = "workspace-switch 7"
"Mod+8" = "workspace-switch 8"
"Mod+9" = "workspace-switch 9"
"Mod+Shift+1" = "window-move-to-workspace 1"
"Mod+Shift+2" = "window-move-to-workspace 2"
"Mod+Shift+3" = "window-move-to-workspace 3"
"Mod+Shift+4" = "window-move-to-workspace 4"
"Mod+Shift+5" = "window-move-to-workspace 5"
"Mod+Shift+6" = "window-move-to-workspace 6"
"Mod+Shift+7" = "window-move-to-workspace 7"
"Mod+Shift+8" = "window-move-to-workspace 8"
"Mod+Shift+9" = "window-move-to-workspace 9"
"Mod+WheelUp" = { action = "workspace-previous", cooldown_ms = 150 }
"Mod+WheelDown" = { action = "workspace-next", cooldown_ms = 150 }
"Mod+MouseMiddle" = "layout-scroll-drag"

# Media / brightness (through Noctalia so the OSDs show)
"XF86AudioRaiseVolume" = { action = "spawn noctalia msg volume-up", allow_when_locked = true }
"XF86AudioLowerVolume" = { action = "spawn noctalia msg volume-down", allow_when_locked = true }
"XF86AudioMute" = { action = "spawn noctalia msg volume-mute", allow_when_locked = true, repeat = false }
"XF86AudioPlay" = { action = "spawn noctalia msg media toggle", allow_when_locked = true, repeat = false }
"XF86AudioNext" = { action = "spawn noctalia msg media next", allow_when_locked = true }
"XF86AudioPrev" = { action = "spawn noctalia msg media previous", allow_when_locked = true }
"XF86MonBrightnessUp" = { action = "spawn noctalia msg brightness-up", allow_when_locked = true }
"XF86MonBrightnessDown" = { action = "spawn noctalia msg brightness-down", allow_when_locked = true }
EOF
fi

# Minimal fish config (only if you don't already have one)
mkdir -p "$XDG_CONFIG_HOME/fish"
if [[ ! -f "$XDG_CONFIG_HOME/fish/config.fish" ]]; then
    cat > "$XDG_CONFIG_HOME/fish/config.fish" <<'EOF'
if status is-interactive
    starship init fish | source
    zoxide init fish | source
    direnv hook fish | source
    alias ls 'eza --icons'
end
EOF
fi

# Thunar custom action: right-click a folder -> Open Kitty Here
mkdir -p "$XDG_CONFIG_HOME/Thunar"
if [[ ! -f "$XDG_CONFIG_HOME/Thunar/uca.xml" ]]; then
    cat > "$XDG_CONFIG_HOME/Thunar/uca.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<actions>
<action>
    <icon>kitty</icon>
    <name>Open Kitty Here</name>
    <unique-id>kitty-open-here</unique-id>
    <command>kitty --directory %f</command>
    <description>Open Kitty terminal in this directory</description>
    <patterns>*</patterns>
    <directories/>
</action>
</actions>
EOF
fi

mkdir -p "$XDG_CONFIG_HOME/fish/functions"

# Silence the fish welcome message (an empty fish_greeting function overrides
# the default, even if the copied config sets the variable).
cat > "$XDG_CONFIG_HOME/fish/functions/fish_greeting.fish" <<'EOF'
function fish_greeting
end
EOF

# --- 6. Wallpapers ---
WALLPAPER_REPO="${WALLPAPER_REPO:-https://github.com/Saltyfunnel/Wallpapers.git}"
WALLPAPER_SRC="$HOME/.local/share/wallpapers"
WALLPAPER_DEST="$HOME/Pictures/Wallpapers"

echo "==> Wallpapers"
if [[ ! -d "$WALLPAPER_SRC/.git" ]]; then
    git clone --depth=1 "$WALLPAPER_REPO" "$WALLPAPER_SRC" || true
fi

if [[ -d "$WALLPAPER_SRC" ]]; then
    mkdir -p "$WALLPAPER_DEST"
    (
        cd "$WALLPAPER_SRC"
        find . -path ./.git -prune -o -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 \
            | xargs -0 -r cp --update=none --parents -t "$WALLPAPER_DEST"
    )
fi

# --- 7. Browser & Media ---
echo "==> Zen Browser"
install_pkg zen-browser-bin
xdg-settings set default-web-browser zen.desktop 2>/dev/null || true

echo "==> Spotify + Spicetify"
if install_pkg spotify spicetify-cli; then
    sudo chmod a+wr /opt/spotify
    sudo chmod -R a+wr /opt/spotify/Apps

    mkdir -p "$XDG_CONFIG_HOME/spotify"
    [[ -e "$XDG_CONFIG_HOME/spotify/prefs" ]] || touch "$XDG_CONFIG_HOME/spotify/prefs"

    spicetify backup apply \
        || echo "    WARN: spicetify apply failed. Launch Spotify once, then run 'spicetify backup apply'."
else
    echo "    WARN: Spotify or Spicetify installation failed."
fi

# --- 8. GTK / icon theme defaults + file manager ---
echo "==> GTK / icon theme defaults"
# These can fail from a TTY with no D-Bus session; if so, run them once after first login.
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' \
    || echo "    WARN: gsettings failed. After first login run the gsettings lines in this script."
ICON_THEME='Papirus-Dark'
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
xdg-mime default thunar.desktop inode/directory || true

# --- 9. Services ---
echo "==> Enabling system services"
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable sddm

# --- 10. Shell Default ---
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]]; then
    echo "==> Setting fish as default shell"
    chsh -s /usr/bin/fish
fi

xdg-user-dirs-update

# --- 11. Sanity check: did umbriel-git register a login session? ---
if ! ls /usr/share/wayland-sessions 2>/dev/null | grep -qi umbriel; then
    echo
    echo "    WARN: no Umbriel entry in /usr/share/wayland-sessions."
    echo "    SDDM won't list it until a umbriel.desktop session file exists."
fi

echo
echo "==> Installation complete! Reboot, select Umbriel in SDDM, and Noctalia starts with the session."
echo
echo "Keybinds in the starter config: Super+Return terminal, Super+E Thunar, Super+B Zen,"
echo "Super+C Zed, Super+S Spotify, Super (tap) or Super+Space launcher, Super+O overview,"
echo "Super+H/J/K/L focus, Super+1..9 workspaces, Super+F fullscreen, Super+Q close,"
echo "Super+Escape power menu, Super+Ctrl+Escape quit session."
echo "Add the rest in ~/.config/umbriel/config.toml (run 'umbriel msg --help' for actions)."
echo
echo "After first login:"
echo "  - Noctalia Settings -> Color Scheme -> Templates: toggle on GTK, Qt and Papirus icons"
echo "  - Noctalia Settings -> Umbriel -> Overview: enable type-to-launch if you want it"
echo "  - qt6ct: Color Scheme tab -> pick 'noctalia' -> Apply; Icon Theme tab -> Papirus-Dark"
echo "  - Fully restart Thunar so it picks up the theme"
