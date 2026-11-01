#!/bin/sh
# Render the view composite with SWT under Xvfb. Writes docs/screenshots/*.png.
set -eu
cd "$(dirname "$0")/.."
export GDK_BACKEND=x11
export SWT_GTK3=1
exec xvfb-run -a -s "-screen 0 1400x900x24" mvn -B -Pscreenshot verify
