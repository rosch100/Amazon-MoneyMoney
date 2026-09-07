-- test/test_multi_login_storage.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")
local env = mm.loadPlugin("amazon-bestellungen.lua")

assert(env.normalizeAmazonLoginKey("  X@Y.COM ") == "x@y.com")

LocalStorage = {}
env.activateAmazonLoginStorage("alice@example.com")
assert(LocalStorage._activeLoginKey == "alice@example.com")
LocalStorage.OrderCache = { ORDER_A = { orderCode = "ORDER_A" } }
LocalStorage.cookies = "cookieA=1"
LocalStorage.loginCounter = 3

env.activateAmazonLoginStorage("bob@example.com")
assert(LocalStorage._activeLoginKey == "bob@example.com")
assert(LocalStorage.OrderCache == nil)
assert(LocalStorage.cookies == nil)
LocalStorage.OrderCache = { ORDER_B = { orderCode = "ORDER_B" } }
LocalStorage.cookies = "cookieB=1"

env.activateAmazonLoginStorage("alice@example.com")
assert(LocalStorage._activeLoginKey == "alice@example.com")
assert(LocalStorage.OrderCache.ORDER_A.orderCode == "ORDER_A")
assert(LocalStorage.OrderCache.ORDER_B == nil)
assert(LocalStorage.cookies == "cookieA=1")
assert(LocalStorage.loginCounter == 3)

env.activateAmazonLoginStorage("bob@example.com")
assert(LocalStorage.OrderCache.ORDER_B.orderCode == "ORDER_B")
assert(LocalStorage.OrderCache.ORDER_A == nil)
assert(LocalStorage.cookies == "cookieB=1")

-- Legacy flat state migrates into the first activating login.
LocalStorage = {
  OrderCache = { LEGACY = { orderCode = "LEGACY" } },
  cookies = "legacy=1",
}
env.activateAmazonLoginStorage("legacy@example.com")
assert(LocalStorage._activeLoginKey == "legacy@example.com")
assert(LocalStorage.OrderCache.LEGACY.orderCode == "LEGACY")

assert(env.shouldPersistAmazonLoginSession(LocalStorage) == false,
  "shouldPersistAmazonLoginSession.singleLogin")
assert(env.shouldPersistAmazonLoginSession({}) == false,
  "shouldPersistAmazonLoginSession.empty")
assert(env.shouldPersistAmazonLoginSession(nil) == false,
  "shouldPersistAmazonLoginSession.nil")

-- Two login buckets: persist (skip remote logout) for the active one.
LocalStorage = {
  _activeLoginKey = "bob@example.com",
  logins = {
    ["alice@example.com"] = { cookies = "a=1" },
    ["bob@example.com"] = { cookies = "b=1" },
  },
}
assert(env.shouldPersistAmazonLoginSession(LocalStorage) == true,
  "shouldPersistAmazonLoginSession.multiLogin")

print("test_multi_login_storage OK")
