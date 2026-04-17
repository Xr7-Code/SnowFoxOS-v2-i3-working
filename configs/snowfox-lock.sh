#!/bin/bash
# SnowFoxOS — Smart Lock
# Sperrt nicht wenn Video/Audio aktiv ist

# Prüfen ob ein Mediaplayer aktiv ist
if playerctl status 2>/dev/null | grep -q "Playing"; then
    exit 0
fi

# Prüfen ob mpv oder ein Browser im Fullscreen ist
FULLSCREEN=$(xdotool getactivewindow getwindowgeometry 2>/dev/null | grep -c "$(xrandr | grep ' connected primary' | grep -oP '\d+x\d+' | head -1)")
if [[ "$FULLSCREEN" -gt 0 ]]; then
    # Aktives Fenster prüfen
    WM_CLASS=$(xdotool getactivewindow getwindowclassname 2>/dev/null)
    if echo "$WM_CLASS" | grep -qiE "mpv|vlc|firefox|chromium|brave|chrom"; then
        exit 0
    fi
fi

# Alles OK — sperren
i3lock -c 000000
