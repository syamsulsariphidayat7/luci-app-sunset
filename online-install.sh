#!/bin/sh
# ==========================================================================
#  luci-app-sunset - installer ONLINE (OpenWrt, ash)
#  Memasang panel Sunset (Services -> Sunset) dari GitHub.
#
#  Satu baris di STB (repo harus SUDAH di-push & Public):
#     curl -fsSL https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-install.sh | sh
#  atau kalau curl tidak ada (OpenWrt bawaan biasanya hanya punya wget):
#     wget -qO- https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-install.sh | sh
#
#  Yang didownload adalah tarball RILIS TERBARU repo ini (tag git
#  terakhir), lalu install.sh di dalamnya dijalankan. Pilihan lain:
#     VERSION=0.1.0 sh online-install.sh   -> paksa tag rilis tertentu
#     BRANCH=main   sh online-install.sh   -> ambil branch mentah (dev)
#  Kalau repo belum punya tag sama sekali, otomatis jatuh ke branch main.
#  Salinan aplikasi disimpan ke /root/luci-app-sunset supaya
#  uninstall.sh selalu tersedia di dalam STB untuk rollback, dan
#  uninstaller juga disalin ke /root/luci-app-sunset-uninstall.sh.
#
#  Ingat: aplikasi ini cuma tampilan. Backend-nya tetap deployment
#  me-web-sunset di Vercel (https://shoot.boundless.my.id) dan setelah
#  install kamu tetap perlu mengisi LUCI_API_SECRET sekali di tab
#  Pengaturan (nilainya sama dengan env LUCI_API_SECRET di Vercel).
# ==========================================================================
set -e

if [ ! -f /etc/openwrt_release ]; then
	echo "STOP: script ini untuk DI DALAM STB (OpenWrt), bukan di PC/laptop." >&2
	exit 1
fi

REPO="syamsulsariphidayat7/luci-app-sunset"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT INT TERM

fetch() { # $1=url $2=output-file
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1" -o "$2"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		echo "[sunset] ERROR: curl dan wget tidak ditemukan." >&2
		echo "[sunset] Install salah satu dulu, misal: opkg update && opkg install curl" >&2
		echo "[sunset] (di OpenWrt 24.10 berbasis apk: apk update && apk add curl)" >&2
		exit 1
	fi
}

REFDESC=""
if [ -n "$BRANCH" ]; then
	URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
	REFDESC="branch $BRANCH"
elif [ -n "$VERSION" ]; then
	TAG="v${VERSION#v}"
	URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
	REFDESC="rilis $TAG"
else
	TAG=""
	if fetch "https://api.github.com/repos/$REPO/tags?per_page=1" "$TMPD/tags.json" 2>/dev/null; then
		TAG=$(grep -o '"name": *"[^"]*"' "$TMPD/tags.json" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
	fi
	if [ -n "$TAG" ]; then
		URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
		REFDESC="rilis terbaru $TAG"
	else
		echo "[sunset] Repo belum punya tag rilis; pakai branch main."
		URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
		REFDESC="branch main"
	fi
fi

echo "[sunset] Download $REFDESC: $URL ..."
fetch "$URL" "$TMPD/app.tar.gz"

echo "[sunset] Ekstrak..."
tar -xzf "$TMPD/app.tar.gz" -C "$TMPD"
ROOT=$(find "$TMPD" -maxdepth 1 -type d -name 'luci-app-sunset-*' | head -1)
if [ -z "$ROOT" ] || [ ! -f "$ROOT/install.sh" ]; then
	echo "[sunset] ERROR: isi tarball tidak seperti yang diharapkan." >&2
	echo "[sunset] Cek lagi: repo sudah di-push? ref '$REFDESC' ada? repo Public?" >&2
	exit 1
fi

echo ""
echo "[sunset] ===== Memasang luci-app-sunset ($REFDESC) ====="
( cd "$ROOT" && sh install.sh )

# Simpan salinan untuk rollback/copot tanpa perlu download ulang.
rm -rf /root/luci-app-sunset
cp -r "$ROOT" /root/luci-app-sunset
cp -f "$ROOT/uninstall.sh" /root/luci-app-sunset-uninstall.sh
chmod 755 /root/luci-app-sunset-uninstall.sh

echo ""
echo "[sunset] SELESAI ($REFDESC). Buka LuCI -> Services -> Sunset (hard refresh: Ctrl+F5)."
echo "[sunset] Pertama kali: isi Secret di tab Pengaturan (sama dengan env LUCI_API_SECRET di Vercel)."
echo "[sunset] Copot aplikasi:   sh /root/luci-app-sunset-uninstall.sh"
