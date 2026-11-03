#!/bin/sh
# ==========================================================================
#  luci-app-sunset - uninstaller (OpenWrt, ash)
#  Menghapus file aplikasi (controller + view) dan membersihkan cache.
#  Config /etc/config/sunset (berisi secret) DIPERTAHANKAN, kecuali
#  dijalankan dengan argumen:  sh uninstall.sh purge
# ==========================================================================
if [ ! -f /etc/openwrt_release ]; then
  echo "STOP: script ini untuk DI DALAM STB (OpenWrt), bukan di PC/laptop."
  exit 1
fi
set -e

echo "[sunset] Menghapus file aplikasi..."
rm -f /usr/lib/lua/luci/controller/sunset.lua
rm -rf /usr/lib/lua/luci/view/sunset

if [ "$1" = "purge" ]; then
  echo "[sunset] purge: config /etc/config/sunset ikut dihapus."
  rm -f /etc/config/sunset
else
  echo "[sunset] Config /etc/config/sunset dipertahankan (pakai argumen 'purge' untuk menghapusnya juga)."
fi

echo "[sunset] Membersihkan cache LuCI + restart uhttpd..."
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache /tmp/luci-modulecache.* 2>/dev/null || true
rm -rf /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart

echo "[sunset] SELESAI. Menu Services -> Sunset sudah hilang."
