# luci-app-sunset

Panel **LuCI** untuk manajemen akun **MyXL (XL Axiata)** — versi tampilan
web dari bot Telegram `me-web-sunset`. Menu: **LuCI → Services → Sunset**.

Tab: **Welcome** (akun aktif, saldo, tier/poin, ringkasan kuota) ·
**Kuota** (paket aktif + sisa kuota per paket) · **Beli** (family code →
daftar paket → konfirmasi → Pulsa/QRIS/decoy) · **Bookmark** (template
beli: beli cepat, ubah, duplikat, hapus, maks 50/nomor) · **Pengaturan**
(URL backend + secret).

## Arsitektur

Aplikasi ini **hanya tampilan**. Semua logika XL (crypto, token,
pembelian) tetap berjalan di backend `me-web-sunset` di Vercel —
tidak ada key XL apa pun di perangkat OpenWrt.

```
Browser (LAN) ──► LuCI di STB (halaman ini)
                     │  fetch HTTPS dari browser, header x-luci-secret
                     ▼
              Vercel: me-web-sunset /api/luci/*
                     ▼
              API XL / Upstash KV
```

Di perangkat hanya tersimpan dua hal di UCI `sunset`
(`/etc/config/sunset`): `api_url` (default
`https://shoot.boundless.my.id`) dan `secret`.

## Syarat

1. OpenWrt 24.10 dengan LuCI (pola controller Lua + view `.htm`,
   sama seperti hg680pcls / luci-app-boundless-theme).
2. Backend `me-web-sunset` sudah ter-deploy dan env **`LUCI_API_SECRET`**
   terisi di Vercel. Tanpa env itu, semua API LuCI ditolak server
   (fail-closed).
3. Browser dipakai dari jaringan yang bisa mengakses backend
   (internet) — panggilan API dilakukan browser, bukan STB.

## Install (di STB)

### Cara online (curl) — disarankan

Repo ini harus sudah di-push ke GitHub sebagai repo **Public**
`syamsulsariphidayat7/luci-app-sunset`. Setelah itu, satu baris di STB:

```sh
curl -fsSL https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-install.sh | sh
```

Kalau `curl` tidak ada (OpenWrt bawaan biasanya hanya punya `wget`):

```sh
wget -qO- https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-install.sh | sh
```

Yang dipasang adalah rilis bertanda tag terbaru; bila repo belum punya
tag, dipakai branch `main`. Paksa versi/branch tertentu bila perlu:

```sh
VERSION=0.1.0 sh online-install.sh   # tag rilis tertentu
BRANCH=main   sh online-install.sh   # branch mentah
```

Copot online (config dipertahankan):

```sh
curl -fsSL https://raw.githubusercontent.com/syamsulsariphidayat7/luci-app-sunset/main/online-uninstall.sh | sh
```

### Cara manual (scp)

```sh
scp -r luci-app-sunset root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'cd /tmp/luci-app-sunset && sh install.sh'
```

Installer menyalin controller + view, membuat semua direktori target
(`mkdir -p`), **tidak menimpa** `/etc/config/sunset` yang sudah ada
(secret aman saat install ulang), membersihkan cache LuCI, dan
me-restart uhttpd.

## Setup pertama kali

1. Buka **LuCI → Services → Sunset** (hard refresh `Ctrl+F5` bila perlu).
2. Halaman otomatis membuka tab **Pengaturan** karena secret masih kosong.
3. Isi **Secret** dengan nilai yang sama persis dengan `LUCI_API_SECRET`
   di Vercel. URL backend sudah terisi default
   `https://shoot.boundless.my.id` — ubah hanya bila deployment pindah.
4. Klik **Simpan Pengaturan**. Setelah itu:
   - Belum ada akun → tab Welcome menampilkan form login OTP
     (nomor XL → kode 6 digit dari SMS → Masuk).
   - Sudah ada akun (dari bot Telegram, data yang sama) → Welcome
     langsung menampilkan saldo & kuota nomor aktif.

## Uninstall

```sh
sh uninstall.sh         # hapus aplikasi, config (secret) dipertahankan
sh uninstall.sh purge   # hapus aplikasi + config
```

## Berkas

| Path | Isi |
|---|---|
| `usr/lib/lua/luci/controller/sunset.lua` | Menu + endpoint lokal `config` (GET) & `saveconfig` (POST, CSRF) |
| `usr/lib/lua/luci/view/sunset/dashboard.htm` | UI satu halaman (vanilla JS) |
| `etc/config/sunset` | UCI: `api_url` + `secret` |
| `install.sh` / `uninstall.sh` | Installer / uninstaller (ash) |
| `PLAN.md` | Dokumen rancangan yang disetujui |

oleh Syamsul Sarip Hidayat · Boundless
