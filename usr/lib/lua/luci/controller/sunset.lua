module("luci.controller.sunset", package.seeall)

-- luci-app-sunset: panel LuCI untuk manajemen akun MyXL (Sunset).
-- Aplikasi ini KULIT TAMPILAN saja: semua logika XL (crypto, token,
-- pembelian) tetap di backend me-web-sunset di Vercel. Controller ini
-- hanya menyediakan dua endpoint lokal:
--   GET  config     -> { api_url, secret, has_secret } dari UCI sunset
--   POST saveconfig -> simpan api_url + secret ke UCI sunset
-- Halaman (view sunset/dashboard) memakai api_url + secret itu untuk
-- memanggil https://<backend>/api/luci/* langsung dari browser dengan
-- header x-luci-secret. Tidak ada key XL apa pun di perangkat ini.
-- Pola mengikuti hg680pcls / luci-app-boundless-theme.

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
end

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
