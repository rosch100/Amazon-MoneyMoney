-- Regression for Amazon's 2026 claim-collect markup (issue #7 follow-up).
-- The email step uses id "auth-credential-autofill-hint" and subPageType
-- "FullPageUnifiedClaimCollect". Must still count as claim-collect, so the
-- autofill password is not sent on the email step.
-- Run: ./test/run.sh test/test_claim_collect_amazon_markup_2026.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local claimHtml = [[<html><body>
<form id="ap_login_form" name="signIn" method="post" action="https://www.amazon.de/ax/claim">
  <input type="hidden" name="appAction" value="SIGNIN_CLAIM_COLLECT"/>
  <input type="hidden" name="subPageType" value="FullPageUnifiedClaimCollect"/>
  <input type="text" id="ap_email_login" name="email" value=""/>
  <input type="password" maxlength="1024" id="auth-credential-autofill-hint" name="password" class="a-input-text aok-hidden"/>
</form>
</body></html>]]

local passwordHtml = [[<html><body>
<form name="signIn" method="post" action="https://www.amazon.de/ap/signin">
  <input type="hidden" name="appAction" value="SIGNIN_PASSWORD_ASSERT"/>
  <input type="hidden" name="email" id="ap_email" value="user@example.com"/>
  <input type="password" id="ap_password" name="password" value=""/>
</form>
</body></html>]]

local loggedInHtml = [[<html><body>
<form action="/gp/css/order-history">
  <select name="timeFilter"><option value="last30">30 Tage</option></select>
</form>
<span class="nav-shortened-name">Ada</span>
</body></html>]]

local env = mm.loadPlugin("amazon-bestellungen.lua")
env.LocalStorage = {
  loginCounter = 0,
  patcher = {},
}

assert(env.isAmazonClaimCollectPage(mm.HTML(claimHtml)) == true,
  "2026 claim-collect markup must be detected as claim-collect")
assert(env.isAmazonPasswordSignInPage(mm.HTML(claimHtml)) == false,
  "2026 claim-collect markup must not be treated as the password step")

local posts = {}
local function formHasParam(body, key)
  if type(body) ~= "string" then
    return false
  end
  for part in body:gmatch("[^&]+") do
    if part:match("^([^=]*)") == key then
      return true
    end
  end
  return false
end

env.connectShop = function()
  return mm.HTML(claimHtml)
end
env.connectShopForm = function(form)
  local _, _, body = form:submit()
  posts[#posts + 1] = {
    body = body or "",
    hasPasswordParam = formHasParam(body, "password"),
  }
  if #posts == 1 then
    return mm.HTML(passwordHtml)
  end
  return mm.HTML(loggedInHtml)
end

env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret-pw"},
  true)

assert(#posts >= 1, "login must submit the email step")
assert(posts[1].hasPasswordParam == false,
  "email step must not send the password, body=" .. tostring(posts[1].body))
assert(not tostring(posts[1].body):find("secret-pw", 1, true),
  "email step body must not contain the real password")
