#!/usr/bin/env bash
# AkyuzIDE başlatıcı
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPIMAGE="$SCRIPT_DIR/release/AkyuzIDE-0.0.0.AppImage"

if [ ! -f "$APPIMAGE" ]; then
  echo "AppImage bulunamadı: $APPIMAGE"
  exit 1
fi

exec "$APPIMAGE" --no-sandbox "$@"
