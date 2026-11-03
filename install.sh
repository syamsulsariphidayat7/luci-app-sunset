#!/bin/sh
# ==========================================================================
#  luci-app-sunset - installer (OpenWrt, ash)
#  Jalankan DARI DALAM folder aplikasi ini di STB, contoh:
#     scp -r luci-app-sunset root@192.168.1.1:/tmp/
#     ssh root@192.168.1.1 'cd /tmp/luci-app-sunset && sh install.sh'
#  Memasang panel Sunset (Services -> Sunset) di LuCI. Config yang sudah
#  ada (termasuk secret yang sudah terisi) selalu DIPERTAHANKAN.
# ==========================================================================
if [ ! -f /etc/openwrt_release ]; then
  echo "STOP: script ini untuk DI DALAM STB (OpenWrt), bukan di PC/laptop."
  echo "Kirim folder aplikasi ke STB lalu jalankan di sana, contoh:"
  echo "  scp -r luci-app-sunset root@192.168.1.1:/tmp/"
  echo "  ssh root@192.168.1.1 'cd /tmp/luci-app-sunset && sh install.sh'"
  exit 1
fi
set -e

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CTL="usr/lib/lua/luci/controller/sunset.lua"
VIEWDIR="usr/lib/lua/luci/view/sunset"
CFG="etc/config/sunset"
VERFILE="VERSION"

if [ ! -f "$DIR/$CTL" ] || [ ! -f "$DIR/$VIEWDIR/dashboard.htm" ] || [ ! -f "$DIR/$CFG" ] || [ ! -f "$DIR/$VERFILE" ]; then
  echo "[sunset] ERROR: file aplikasi tidak lengkap di $DIR" >&2
  echo "[sunset] Jalankan script dari dalam folder luci-app-sunset." >&2
  exit 1
fi

echo "[sunset] Menyalin file..."
mkdir -p /usr/lib/lua/luci/controller
mkdir -p "/$VIEWDIR"
mkdir -p /etc/config
cp -f "$DIR/$CTL" "/$CTL"
cp -f "$DIR/$VIEWDIR/dashboard.htm" "/$VIEWDIR/dashboard.htm"
cp -f "$DIR/$VERFILE" "/$VIEWDIR/VERSION"
if [ -f /etc/config/sunset ]; then
  echo "[sunset] Config yang sudah ada dipertahankan (secret tidak ditimpa)"
else
  cp -f "$DIR/$CFG" /etc/config/sunset
fi
chmod 644 "/$CTL" "/$VIEWDIR/dashboard.htm" "/$VIEWDIR/VERSION" /etc/config/sunset

echo "[sunset] Membersihkan cache LuCI + restart uhttpd..."
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache /tmp/luci-modulecache.* 2>/dev/null || true
rm -rf /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart

echo "[sunset] Verifikasi:"
grep -q "luci.controller.sunset" "/$CTL" && echo "[sunset] controller OK"
[ -f "/$VIEWDIR/dashboard.htm" ] && echo "[sunset] view OK"
[ -f "/$VIEWDIR/VERSION" ] && echo "[sunset] versi OK ($(cat "/$VIEWDIR/VERSION"))"
[ -f /etc/config/sunset ] && echo "[sunset] config OK"
echo ""
echo "[sunset] SELESAI. Langkah berikutnya:"
echo "  1. Pastikan backend me-web-sunset sudah ter-deploy dengan env"
echo "     LUCI_API_SECRET terisi di Vercel."
echo "  2. Buka LuCI -> Services -> Sunset (hard refresh: Ctrl+F5)."
echo "  3. Di tab Pengaturan, isi Secret dengan nilai LUCI_API_SECRET"
echo "     yang sama, lalu Simpan. URL backend sudah terisi default:"
echo "     https://shoot.boundless.my.id"
