#!/bin/bash
# SnowFoxOS — Netzwerk-Manager via Rofi (X11)

NETWORKS=$(nmcli -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    INUSE=$(echo "$line" | cut -c1-8 | xargs)
    SSID=$(echo "$line" | cut -c9-31 | xargs)
    SIGNAL=$(echo "$line" | cut -c32-39 | xargs)
    SECURITY=$(echo "$line" | cut -c40- | xargs)
    [[ -z "$SSID" || "$SSID" == "--" ]] && continue
    ICON=$([ "$INUSE" = "*" ] && echo "✓" || echo " ")
    SEC_LABEL=$([ "$SECURITY" = "--" ] && echo "OPEN" || echo "$SECURITY")
    printf "%s %-30s %3s%%  %s\n" "$ICON" "$SSID" "$SIGNAL" "$SEC_LABEL"
done)

EXTRAS="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WiFi an/aus
  Verbindung trennen
  Ethernet-Status
  Netzwerk-Details"

CHOICE=$(echo -e "$NETWORKS\n$EXTRAS" | rofi -dmenu \
    -p "Netzwerk" \
    -theme ~/.config/rofi/config.rasi \
    -width 500 \
    -lines 12)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    *"WiFi an/aus"*)
        STATE=$(nmcli radio wifi)
        if [[ "$STATE" == "enabled" ]]; then
            nmcli radio wifi off
            notify-send "🦊 SnowFox" "WiFi deaktiviert"
        else
            nmcli radio wifi on
            notify-send "🦊 SnowFox" "WiFi aktiviert"
        fi
        ;;
    *"Verbindung trennen"*)
        ACTIVE=$(nmcli -t -f NAME connection show --active | head -1)
        if [[ -n "$ACTIVE" ]]; then
            nmcli connection down "$ACTIVE"
            notify-send "🦊 SnowFox" "Getrennt von: $ACTIVE"
        else
            notify-send "🦊 SnowFox" "Keine aktive Verbindung"
        fi
        ;;
    *"Ethernet-Status"*)
        ETH=$(nmcli device status | grep ethernet)
        notify-send "🦊 SnowFox Ethernet" "$ETH"
        ;;
    *"Netzwerk-Details"*)
        INFO=$(nmcli device show | grep -E "GENERAL.DEVICE|GENERAL.STATE|IP4.ADDRESS|IP4.GATEWAY" | head -12)
        notify-send "🦊 SnowFox Netzwerk" "$INFO"
        ;;
    *"━━━"*)
        exit 0
        ;;
    *)
        SSID=$(echo "$CHOICE" | cut -c3- | awk '{print $1}' | xargs)
        [[ -z "$SSID" ]] && exit 0

        CURRENT=$(nmcli -t -f active,ssid dev wifi | grep "^yes" | cut -d: -f2)
        if [[ "$CURRENT" == "$SSID" ]]; then
            PORTAL_URL=$(curl -s -I --max-time 3 http://detectportal.firefox.com/success.txt \
                | grep -i "^location:" | awk '{print $2}' | tr -d '\r')
            if [[ -n "$PORTAL_URL" ]]; then
                notify-send "🦊 SnowFox" "Captive Portal erkannt"
                xdg-open "$PORTAL_URL" &
            else
                notify-send "🦊 SnowFox" "Bereits verbunden mit: $SSID"
            fi
            exit 0
        fi

        SECURITY=$(nmcli -f SSID,SECURITY device wifi list | grep "^${SSID} " | awk '{print $NF}' | head -1)

        if nmcli connection show "$SSID" &>/dev/null; then
            nmcli connection up "$SSID" && \
                notify-send "🦊 SnowFox" "Verbunden mit: $SSID" || \
                notify-send "🦊 SnowFox" "Verbindung fehlgeschlagen"

        elif [[ "$SECURITY" = "--" || "$CHOICE" == *"OPEN"* ]]; then
            notify-send "🦊 SnowFox" "Verbinde mit: $SSID"
            nmcli device wifi connect "$SSID" 2>/dev/null
            sleep 3
            PORTAL_URL=$(curl -s -I --max-time 3 http://detectportal.firefox.com/success.txt \
                | grep -i "^location:" | awk '{print $2}' | tr -d '\r')
            if [[ -n "$PORTAL_URL" ]]; then
                notify-send "🦊 SnowFox" "Captive Portal — Browser wird geöffnet"
                xdg-open "$PORTAL_URL" &
            else
                notify-send "🦊 SnowFox" "Verbunden mit: $SSID"
            fi

        else
            PASS=$(rofi -dmenu \
                -p "Passwort für $SSID" \
                -theme ~/.config/rofi/config.rasi \
                -width 400 \
                -lines 0 \
                -password)

            if [[ -n "$PASS" ]]; then
                nmcli device wifi connect "$SSID" password "$PASS" && \
                    notify-send "🦊 SnowFox" "Verbunden mit: $SSID" || \
                    notify-send "🦊 SnowFox" "Verbindung fehlgeschlagen — falsches Passwort?"
            else
                nmcli device wifi connect "$SSID" && \
                    notify-send "🦊 SnowFox" "Verbunden mit: $SSID" || \
                    notify-send "🦊 SnowFox" "Verbindung fehlgeschlagen"
            fi
        fi
        ;;
esac
