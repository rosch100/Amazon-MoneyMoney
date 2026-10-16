-- Claim-collect is the email step. The hidden password input is an autofill hint.
-- Sending the real password there skips the password page and never reaches OTP.
-- Run: ./test/run.sh test/test_claim_collect_signin.lua
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local claimHtml = [[<html><body>
<form name="signIn" method="post" action="https://www.amazon.de/ax/claim">
  <input type="hidden" name="subPageType" value="SignInClaimCollect"/>
  <input type="email" name="email" id="ap_email" value=""/>
  <input type="password" id="ap-credential-autofill-hint" name="password" class="a-input-text hide" value=""/>
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
  cookies = "session=keep",
}

local posts = {}
env.connectShop = function()
  return mm.HTML(claimHtml)
end
env.connectShopForm = function(form)
  posts[#posts + 1] = {
    email = form:xpath('//*[@name="email"]'):attr("value"),
    password = form:xpath('//*[@name="password"]'):attr("value"),
    subPageType = form:xpath('//*[@name="subPageType"]'):attr("value"),
    passwordId = form:xpath('//*[@name="password"]'):attr("id"),
  }
  if #posts == 1 then
    return mm.HTML(passwordHtml)
  end
  return mm.HTML(loggedInHtml)
end

local result = env.InitializeSession2(
  env.ProtocolWebBanking,
  "Amazon",
  1,
  {"user@example.com", "secret-pw"},
  true)

assert(#posts >= 2, "login must submit claim-collect and then the password page, got " .. tostring(#posts))
assert(posts[1].subPageType == "SignInClaimCollect")
assert(posts[1].email == "user@example.com", "claim step must send the email")
assert(posts[1].password == "", "claim step must not send the autofill password, got " .. tostring(posts[1].password))
assert(posts[2].passwordId == "ap_password")
assert(posts[2].password == "secret-pw", "password step must send the password")
assert(result == nil, "login must finish after the password page, got " .. tostring(result))

local claimPage = mm.HTML(claimHtml)
assert(env.isAmazonClaimCollectPage(claimPage) == true)
assert(env.isAmazonPasswordSignInPage(claimPage) == false,
  "hidden autofill password is not the password step")
assert(env.isAmazonPasswordSignInPage(mm.HTML(passwordHtml)) == true)
