#!/bin/bash
# SnowFoxOS — Power Menu via Rofi

CHOICE=$(echo -e "  Shutdown\n  Reboot\n  Logout\n  Suspend\n  Lock" | \
    rofi -dmenu \
    -p "Power" \
    -theme ~/.config/rofi/config.rasi \
    -width 250 \
    -lines 5)

case "$CHOICE" in
    *Shutdown)  systemctl poweroff ;;
    *Reboot)    systemctl reboot ;;
    *Logout)    i3-msg exit ;;
    *Suspend)   systemctl suspend ;;
    *Lock)      i3lock -c 000000 ;;
esac
