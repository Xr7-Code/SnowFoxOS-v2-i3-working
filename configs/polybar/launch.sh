#!/bin/bash
# SnowFoxOS — Polybar Starter
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done
polybar snowfox 2>/tmp/polybar.log &
