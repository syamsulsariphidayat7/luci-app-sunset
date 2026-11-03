#!/bin/sh
# ==========================================================================
#  luci-app-sunset - pencopot ONLINE (OpenWrt, ash)
#
#  Satu baris di STB:
#     curl -fsSL https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-uninstall.sh | sh
#  atau:
#     wget -qO- https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-uninstall.sh | sh
#
#  Cara kerja: kalau salinan lokal dari online-install masih ada
#  (/root/luci-app-sunset-uninstall.sh), itu yang dipakai — tidak perlu
#  download. Kalau tidak ada, uninstall.sh diunduh dari branch main
#  repo lalu dijalankan.
#  Config (/etc/config/sunset, berisi secret) DIPERTAHANKAN. Untuk
#  menghapus config juga, jalankan salinan lokal dengan argumen purge:
#     sh /root/luci-app-sunset-uninstall.sh purge
# ==========================================================================
set -e

if [ ! -f /etc/openwrt_release ]; then
	echo "STOP: script ini untuk DI DALAM STB (OpenWrt), bukan di PC/laptop." >&2
	exit 1
fi

if [ -f /root/luci-app-sunset-uninstall.sh ]; then
	echo "[sunset] Memakai uninstaller lokal: /root/luci-app-sunset-uninstall.sh"
	exec sh /root/luci-app-sunset-uninstall.sh "$@"
fi

REPO="syamsulsariphidayat7/luci-app-sunset"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT INT TERM

echo "[sunset] Download uninstaller dari branch main..."
if command -v curl >/dev/null 2>&1; then
	curl -fsSL "https://raw.githubusercontent.com/$REPO/main/uninstall.sh" -o "$TMPD/uninstall.sh"
elif command -v wget >/dev/null 2>&1; then
	wget -q -O "$TMPD/uninstall.sh" "https://raw.githubusercontent.com/$REPO/main/uninstall.sh"
else
	echo "[sunset] ERROR: curl dan wget tidak ditemukan." >&2
	exit 1
fi

exec sh "$TMPD/uninstall.sh" "$@"
