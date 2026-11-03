module("luci.controller.sunset", package.seeall)

-- luci-app-sunset: panel LuCI untuk manajemen akun MyXL (Sunset).
-- Aplikasi ini KULIT TAMPILAN saja: semua logika XL (crypto, token,
-- pembelian) tetap di backend me-web-sunset di Vercel. Controller ini
-- hanya menyediakan endpoint lokal:
--   GET  config     -> { api_url, secret, has_secret } dari UCI sunset
--   POST saveconfig -> simpan api_url + secret ke UCI sunset
--   GET  version    -> { installed } dari stempel VERSION di folder view
--   GET  check      -> bandingkan versi terpasang vs tag terbaru GitHub
--   POST update     -> jalankan online-install rilis terbaru (detached)
--   GET  updatelog  -> log + rc proses update untuk polling halaman
-- Halaman (view sunset/dashboard) memakai api_url + secret itu untuk
-- memanggil https://<backend>/api/luci/* langsung dari browser dengan
-- header x-luci-secret. Tidak ada key XL apa pun di perangkat ini.
-- Pola mengikuti hg680pcls / luci-app-boundless-theme (termasuk mesin
-- proses detached + log/rc/pid di /tmp untuk update).

function index()
	if not nixio.fs.access("/etc/config/sunset") then
		return
	end
	entry({"admin", "services", "sunset"},
		template("sunset/dashboard"), "Sunset", 90)
	entry({"admin", "services", "sunset", "config"},
		call("action_config")).leaf = true
	entry({"admin", "services", "sunset", "saveconfig"},
		post("action_saveconfig")).leaf = true
	entry({"admin", "services", "sunset", "version"},
		call("action_version")).leaf = true
	entry({"admin", "services", "sunset", "check"},
		call("action_check")).leaf = true
	entry({"admin", "services", "sunset", "update"},
		post("action_update")).leaf = true
	entry({"admin", "services", "sunset", "updatelog"},
		call("action_updatelog")).leaf = true
end

local REPO_SLUG    = "syamsulsariphidayat7/luci-app-sunset"
local REPO_API     = "https://api.github.com/repos/" .. REPO_SLUG
local REPO_RAW     = "https://raw.githubusercontent.com/" .. REPO_SLUG
local VERSION_FILE = "/usr/lib/lua/luci/view/sunset/VERSION"
local UPDATE_LOG   = "/tmp/sunset-update.log"
local UPDATE_RC    = "/tmp/sunset-update.rc"
local UPDATE_PID   = "/tmp/sunset-update.pid"
local UPDATE_SCRIPT = "/tmp/sunset-online-install.sh"

local function write_json(tbl, status)
	if status then luci.http.status(status, status == 400 and "Bad Request" or "Error") end
	luci.http.prepare_content("application/json")
	luci.http.write(luci.jsonc.stringify(tbl))
end

-- Wajib POST + token CSRF yang sah (sama seperti luci-app-boundless-theme;
-- entry post() juga memaksa token dari sisi dispatcher).
local function require_post()
	local disp = luci.dispatcher
	if disp and disp.test_post_security then
		return disp.test_post_security()
	end
	if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
		luci.http.status(405, "Method Not Allowed")
		return false
	end
	local tok  = luci.http.formvalue("token")
	local want = disp and disp.context and disp.context.authtoken
	if tok and want and tok == want then
		return true
	end
	luci.http.status(403, "Forbidden")
	return false
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

local function read_tail(path, max)
	local f = io.open(path, "rb")
	if not f then return "" end
	local size = f:seek("end") or 0
	local off = size - max
	if off < 0 then off = 0 end
	f:seek("set", off)
	local data = f:read("*a") or ""
	f:close()
	return data
end

local function read_trim(path)
	local s = read_file(path)
	if not s then return nil end
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	return s
end

-- Versi terpasang dari stempel VERSION (disalin install.sh sejak
-- 0.2.0). Install dari 0.1.0 belum punya stempel -> "?".
local function installed_version()
	local v = read_trim(VERSION_FILE)
	if not v then return "?" end
	return (v:gsub("^v", ""))
end

-- Ambil teks dari URL: curl bila ada, kalau tidak wget
-- (pola luci-app-boundless-theme).
local function fetch_text(url)
	local out = luci.sys.exec(string.format(
		"if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 6 --max-time 20 %s; "
		.. "elif command -v wget >/dev/null 2>&1; then wget -qO- --timeout=20 %s; fi 2>/dev/null",
		luci.util.shellquote(url), luci.util.shellquote(url)))
	return out or ""
end

-- Tag rilis terbaru dari API GitHub (per_page=1 = tag pertama =
-- yang terbaru untuk repo ini). Parsing "name" pertama, tanpa jq —
-- cara yang sama seperti online-install.sh. Nil bila gagal.
local function latest_tag()
	local out = fetch_text(REPO_API .. "/tags?per_page=1")
	if not out or out == "" then return nil end
	local tag = out:match('"name"%s*:%s*"([^"]+)"')
	if not tag or tag == "" then return nil end
	return tag
end

local function update_running()
	if read_trim(UPDATE_RC) then return false end
	local pid = read_trim(UPDATE_PID)
	if pid and pid:match("^%d+$") and nixio.fs.access("/proc/" .. pid) then
		return true
	end
	return false
end

local function get_settings()
	local uci = luci.model.uci.cursor()
	return {
		api_url = uci:get("sunset", "settings", "api_url") or "",
		secret  = uci:get("sunset", "settings", "secret") or "",
	}
end

-- GET /config — dibaca halaman saat load untuk tahu backend + secret.
-- Secret memang ikut dibalas: halaman ini sudah di balik login LuCI dan
-- browser membutuhkannya sebagai header x-luci-secret ke backend.
function action_config()
	local cfg = get_settings()
	write_json({
		ok = true,
		api_url = cfg.api_url,
		secret = cfg.secret,
		has_secret = cfg.secret ~= "",
	})
end

-- POST /saveconfig { api_url, secret } — simpan pengaturan backend.
function action_saveconfig()
	if not require_post() then return end
	local http = luci.http

	local api_url = (http.formvalue("api_url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
	api_url = api_url:gsub("/+$", "")
	local secret = (http.formvalue("secret") or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if api_url ~= "" and not api_url:match("^https?://[^%s\"']+$") then
		return write_json({ ok = false, error = "api_url tidak valid (harus diawali http:// atau https://, tanpa spasi)" }, 400)
	end

	local uci = luci.model.uci.cursor()
	if not uci:get_first("sunset", "settings") then
		uci:section("sunset", "settings", "settings")
	end
	uci:set("sunset", "settings", "api_url", api_url)
	uci:set("sunset", "settings", "secret", secret)
	uci:commit("sunset")

	write_json({ ok = true, api_url = api_url, has_secret = secret ~= "" })
end

-- GET /version — versi aplikasi yang terpasang di perangkat ini.
function action_version()
	write_json({ ok = true, installed = installed_version() })
end

-- GET /check — bandingkan versi terpasang dengan tag rilis terbaru.
function action_check()
	local installed = installed_version()
	local tag = latest_tag()
	if not tag then
		return write_json({ ok = false,
			error = "Gagal menghubungi GitHub. Cek koneksi internet STB.",
			installed = installed }, 502)
	end
	local latest = tag:gsub("^v", "")
	write_json({
		ok = true,
		installed = installed,
		latest = tag,
		update_available = latest ~= installed,
	})
end

-- POST /update — unduh online-install.sh dari tag rilis terbaru dan
-- jalankan DETACHED (setsid/nohup, lepas dari uhttpd yang akan
-- di-restart oleh install.sh di tengah jalan). Wrapper menulis
-- pid-nya sendiri, lalu rc di akhir — rc selalu tertulis walau
-- proses di dalamnya gagal (baris terakhir wrapper, bukan `exit`
-- dari body). Log ke /tmp/sunset-update.log untuk polling UI.
function action_update()
	if not require_post() then return end
	if update_running() then
		return write_json({ ok = false, error = "Update sedang berjalan. Tunggu sampai selesai." }, 409)
	end
	local tag = latest_tag()
	if not tag then
		return write_json({ ok = false,
			error = "Gagal menghubungi GitHub. Cek koneksi internet STB." }, 502)
	end
	local script_url = REPO_RAW .. "/" .. tag .. "/online-install.sh"

	luci.sys.call(string.format("rm -f %s %s %s",
		luci.util.shellquote(UPDATE_LOG),
		luci.util.shellquote(UPDATE_RC),
		luci.util.shellquote(UPDATE_PID)))

	local body = string.format([[
echo "[sunset] Mengunduh online-install.sh rilis %s ..."
if curl -fsSL --connect-timeout 10 --max-time 60 %s -o %s 2>/dev/null || wget -q --timeout=60 %s -O %s 2>/dev/null; then
    sh %s
else
    echo "[sunset] Gagal mengunduh online-install.sh dari GitHub"
    false
fi]],
		tag,
		luci.util.shellquote(script_url),
		luci.util.shellquote(UPDATE_SCRIPT),
		luci.util.shellquote(script_url),
		luci.util.shellquote(UPDATE_SCRIPT),
		luci.util.shellquote(UPDATE_SCRIPT))

	local wrapper = string.format("echo $$ > %s\n%s\necho $? > %s\nrm -f %s",
		UPDATE_PID, body, UPDATE_RC, UPDATE_PID)

	local prefix = ""
	if luci.sys.call("command -v setsid >/dev/null 2>&1") == 0 then
		prefix = "setsid "
	elseif luci.sys.call("command -v nohup >/dev/null 2>&1") == 0 then
		prefix = "nohup "
	end
	luci.sys.call(string.format("%ssh -c %s </dev/null >%s 2>&1 &",
		prefix, luci.util.shellquote(wrapper),
		luci.util.shellquote(UPDATE_LOG)))

	write_json({ ok = true, started = true, latest = tag })
end

-- GET /updatelog — keadaan proses update untuk polling halaman.
-- rc belum ada (nil, jadi tidak ikut di JSON) selama masih berjalan.
function action_updatelog()
	local rc = read_trim(UPDATE_RC)
	local code
	if rc and rc:match("^%-?%d+$") then code = tonumber(rc) end
	write_json({
		ok = true,
		log = read_tail(UPDATE_LOG, 4000),
		rc = code,
		running = update_running(),
	})
end
