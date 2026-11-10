-- Amazon leaks its internal port 8443 into OpenID return URLs.
-- Run: test/run.sh test/test_internal_port_8443.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

local function assertEqual(expected, actual, message)
  assert(expected == actual,
    message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

assertEqual(
  "https://www.amazon.de/your-orders/orders?ref_=nav_orders_first",
  env.absoluteAmazonUrl("https://www.amazon.de:8443/your-orders/orders?ref_=nav_orders_first"),
  "absolute Amazon URL drops internal port")
assertEqual(
  "https://www.Amazon.de/your-orders/orders",
  env.absoluteAmazonUrl("https://www.Amazon.de:8443/your-orders/orders"),
  "mixed-case Amazon host drops internal port")
assertEqual(
  "https://www.amazon.de/ap/signin?openid.return_to=https%3A%2F%2Fwww.amazon.de%2Fyour-orders%2Forders",
  env.absoluteAmazonUrl(
    "/ap/signin?openid.return_to=https%3A%2F%2Fwww.amazon.de%3A8443%2Fyour-orders%2Forders"),
  "encoded return URL drops internal port")
assertEqual(
  "https://www.amazon.de/x",
  env.stripAmazonInternalPort("https://www.amazon.de%3A8443/x"),
  "encoded port is normalized")
assertEqual(
  "https://www.amazon.de/x",
  env.stripAmazonInternalPort("https://www.amazon.de%253A8443/x"),
  "double-encoded port is normalized")
assertEqual("https://www.amazon.de:8443evil/x",
  env.stripAmazonInternalPort("https://www.amazon.de:8443evil/x"),
  "port-like text in a hostname is not changed")
assertEqual("https://www.amazon.de%3A8443evil/x",
  env.stripAmazonInternalPort("https://www.amazon.de%3A8443evil/x"),
  "encoded port-like text in a hostname is not changed")

local encodedReturn = env.amazonBase64Encode(
  "https://www.amazon.de:8443/your-orders/orders?ref_=nav_orders_first")
local body = "appActionToken=abc%2B%2F"
  .. "&openid.return_to=ape%3A" .. encodedReturn:gsub("%+", "%%2B"):gsub("/", "%%2F"):gsub("=", "%%3D")
  .. "&prevRID=ape%3AUVlFNlg%3D"
  .. "&other=https%3A%2F%2Fwww.amazon.de%3A8443%2Fy"
  .. "&otpCode=123456&rememberDevice="
local fixedBody = env.stripAmazonInternalPortFromForm(body)
assert(not fixedBody:find("8443", 1, true), "form body contains no internal port")
assert(fixedBody:find("appActionToken=abc%%2B%%2F"), "unrelated form values remain encoded")
assert(fixedBody:find("prevRID=ape%%3AUVlFNlg%%3D"), "unrelated ape value remains unchanged")
assert(fixedBody:find("&otpCode=123456&rememberDevice=$"), "empty trailing field is preserved")
local returnTo = fixedBody:match("openid%.return_to=([^&]*)")
returnTo = returnTo:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
assertEqual(
  "https://www.amazon.de/your-orders/orders?ref_=nav_orders_first",
  env.amazonBase64Decode(returnTo:match("^ape:(.+)$")),
  "base64-encoded return URL drops internal port")

-- Keep the encoded delimiter intact, including inside base64 ape payloads.
for _, port in ipairs({"%3A8443", "%253A8443"}) do
  for _, suffix in ipairs({"%252Forders", "%253Fref=orders", "%2523orders",
                          "%252forders", "%253fref=orders"}) do
    local expected = "https%253A%252F%252Fwww.amazon.de" .. suffix
    local original = "https%253A%252F%252Fwww.amazon.de" .. port .. suffix
    assertEqual(expected, env.stripAmazonInternalPort(original),
      "encoded URL drops " .. port .. " before " .. suffix)
    local payload = env.amazonBase64Encode(original)
    local form = "openid.return_to=ape%3A"
      .. payload:gsub("%+", "%%2B"):gsub("/", "%%2F"):gsub("=", "%%3D")
    local normalized = env.stripAmazonInternalPortFromForm(form)
    local value = normalized:match("^openid%.return_to=(.*)$")
      :gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    assertEqual(expected, env.amazonBase64Decode(value:match("^ape:(.+)$")),
      "ape payload drops " .. port .. " before " .. suffix)
  end
  assertEqual("https://www.amazon.de" .. port .. "%2541orders",
    env.stripAmazonInternalPort("https://www.amazon.de" .. port .. "%2541orders"),
    "double-encoded non-delimiter preserves port")
end

local ok = pcall(env.absoluteAmazonUrl, "https://evil.example:8443/x")
assert(not ok, "foreign absolute hosts remain rejected")
assertEqual("a=1&b=2", env.stripAmazonInternalPortFromForm("a=1&b=2"),
  "unrelated form body remains byte-identical")

print("test_internal_port_8443 OK")
