#!/bin/bash
rm -r /tmp/.X99-lock
DISPLAY=:99
export DISPLAY
Xvfb :99 -ac -listen tcp -screen 0 1920x1080x24 &
/usr/bin/fluxbox -display :99 -screen 0 &
/usr/bin/x11vnc -display :99 -forever -passwd ${X11VNC_PASSWORD:-password} &
meld
