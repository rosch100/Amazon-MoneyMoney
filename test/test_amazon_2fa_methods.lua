-- Amazon 2FA method classification + submit conformity.
-- Run: ./test/run.sh test/test_amazon_2fa_methods.lua
---@diagnostic disable: duplicate-set-field
package.path = "./test/?.lua;" .. package.path
local mm = require("mm_shim")

local env = mm.loadPlugin("amazon-bestellungen.lua")

local function loadFixture(name)
  local f = assert(io.open("test/fixtures/" .. name, "rb"))
  local body = f:read("*all")
  f:close()
  return mm.HTML(body)
end

-- Channel preference: typed codes; all Amazon device channels supported
assert(env.amazonAuthDeviceChannelScore("x.TOTP") > env.amazonAuthDeviceChannelScore("x.SMS"))
assert(env.amazonAuthDeviceChannelScore("x.SMS") > env.amazonAuthDeviceChannelScore("x.WHATSAPP"))
assert(env.amazonAuthDeviceChannelScore("x.WHATSAPP") > env.amazonAuthDeviceChannelScore("x.EMAIL"))
assert(env.amazonAuthDeviceChannelScore("x.EMAIL") > env.amazonAuthDeviceChannelScore("x.OTHER"))
assert(env.amazonAuthDeviceChannelScore("x.EMAIL") > env.amazonAuthDeviceChannelScore("x.VOICE"))
assert(env.amazonAuthDeviceChannelScore("x.VOICE") > 0)
assert(env.amazonAuthDeviceChannelScore("a.sms") == env.amazonAuthDeviceChannelScore("a.SMS"))
assert(env.amazonAuthDeviceChannelScore("a.whatsapp") == env.amazonAuthDeviceChannelScore("a.WHATSAPP"))
assert(env.amazonAuthDeviceChannelScore("a.SMS") > env.amazonAuthDeviceChannelScore("a.whatsapp"))

local devicePage = mm.HTML([[<html><body>
  <form id="auth-select-device-form">
    <label><input type="radio" name="otpDeviceContext" value="a.VOICE"/>Anruf</label>
    <label><input type="radio" name="otpDeviceContext" value="b.SMS"/>SMS</label>
    <label><input type="radio" name="otpDeviceContext" value="c.EMAIL"/>E-Mail</label>
    <label><input type="radio" name="otpDeviceContext" value="d.TOTP"/>Authenticator</label>
  </form>
</body></html>]])
assert(env.isAmazonAuthDeviceSelectPage(devicePage) == true)
assert(env.isAmazonEnterableOtpPage(devicePage) == false)
assert(env.isAmazonAuthenticationChallengePage(devicePage) == true)
local selected = env.applyPreferredAmazonAuthDeviceSelection(
  devicePage:xpath('//form[@id="auth-select-device-form"]'))
assert(selected == "d.TOTP", "preferred device must be TOTP, got " .. tostring(selected))
assert(devicePage:xpath('//input[@value="d.TOTP"]'):attr("checked") == "checked")
assert(devicePage:xpath('//input[@value="b.SMS"]'):attr("checked") == "")

-- SMS-only device select still chooses SMS (not voice)
local smsOnly = mm.HTML([[<html><body>
  <form id="auth-select-device-form">
    <input type="radio" name="otpDeviceContext" value="a.VOICE"/>
    <input type="radio" name="otpDeviceContext" value="b.SMS"/>
  </form>
</body></html>]])
assert(env.applyPreferredAmazonAuthDeviceSelection(
  smsOnly:xpath('//form[@id="auth-select-device-form"]')) == "b.SMS")

-- CVF SMS + app polling: enterable OTP wins
local cvf = loadFixture("cvf_transactionapproval_sms_otp_20260906.html")
assert(env.isCvfVerificationCodeOtpPage(cvf) == true)
assert(env.isAmazonEnterableOtpPage(cvf) == true)
assert(env.isAmazonAppApprovalPollingPage(cvf) == false,
  "must not poll app approval while SMS OTP form is present")
assert(env.isAmazonAuthenticationChallengePage(cvf) == false)
local loginCh = env.loginOtpChallengeFromHtml(cvf)
assert(type(loginCh) == "table" and loginCh.title == "Zwei-Faktor-Authentifizierung")
assert(string.find(loginCh.challenge, "Telefon", 1, true)
  or string.find(loginCh.challenge, "Bestätigungscode", 1, true))
local switchCh = env.mfaChallengeFromHtml(cvf)
assert(switchCh.title == "Amazon Konto wechseln – 2FA")
local land = env.finishAccountSwitchLanding(cvf)
assert(land.needsMfa == true)

local submitted = nil
env.connectShopForm = function(form)
  submitted = form
  return mm.HTML("<html><body>ok</body></html>")
end
local nextHtml, err = env.submitAmazonMfa(cvf, "111222")
assert(err == nil and nextHtml ~= nil)
assert(submitted:attr("id") == "verification-code-form")
assert(cvf:xpath('//*[@name="otpCode"]'):attr("value") == "111222")
assert(cvf:xpath('//*[@name="otpCodeHidden"]'):attr("value") == "111222")

-- Classic TOTP/SMS MFA form
local classic = mm.HTML([[<html><body>
  <form id="auth-mfa-form"><p>Code aus der Authenticator-App</p>
    <input name="otpCode" type="text"/>
    <input name="rememberDevice" type="checkbox"/>
  </form>
</body></html>]])
assert(env.isAmazonEnterableOtpPage(classic) == true)
assert(env.amazonMfaChallengePrompt(classic):find("Authenticator", 1, true))
submitted = nil
assert(env.submitAmazonMfa(classic, "999888"))
assert(submitted:attr("id") == "auth-mfa-form")

-- App-approval-only page (Amazon-App-Freigabe; no speculative SMS/WhatsApp redirect)
local pollOnly = mm.HTML([[<html><body>
  <form id="pollingForm" action="/ap/cvf/approval/poll">
    <input type="hidden" name="transactionApprovalStatus" value="TransactionPending"/>
  </form>
</body></html>]])
assert(env.isAmazonAppApprovalPollingPage(pollOnly) == true)
assert(env.isAmazonEnterableOtpPage(pollOnly) == false)
assert(env.isAmazonAuthenticationChallengePage(pollOnly) == true)
assert(env.loginOtpChallengeFromHtml(pollOnly) == nil)
assert(env.mfaChallengeFromHtml(pollOnly) == nil)

-- App approval + WhatsApp alternate (2026-09-06): stay on app-poll path
local appWa = loadFixture("cvf_transactionapproval_app_only_whatsapp_20260906.html")
assert(env.isAmazonAppApprovalPollingPage(appWa) == true)
assert(env.isAmazonEnterableOtpPage(appWa) == false)
assert(env.loginOtpChallengeFromHtml(appWa) == nil)
assert(env.isAmazonAuthenticationChallengePage(appWa) == true)

-- VOICE-only device select is still supported
local voiceOnly = mm.HTML([[<html><body>
  <form id="auth-select-device-form">
    <input type="radio" name="otpDeviceContext" value="a.VOICE"/>
  </form>
</body></html>]])
assert(env.applyPreferredAmazonAuthDeviceSelection(
  voiceOnly:xpath('//form[@id="auth-select-device-form"]')) == "a.VOICE")

-- Claims picker + verify
local claims = mm.HTML([[<html><body>
  <form name="claimspicker" action="claimspicker">
    <div>Methode wählen</div>
    <input type="radio" name="option" value="sms"/><span>SMS</span>
    <input type="radio" name="option" value="email"/><span>E-Mail</span>
  </form>
</body></html>]])
assert(env.isAmazonClaimsPickerPage(claims) == true)
assert(env.isAmazonAuthenticationChallengePage(claims) == true)

local verify = mm.HTML([[<html><body>
  <form action="verify">
    <div><div>Code eingeben</div><div>SMS an ****</div></div>
    <input name="code" type="text"/>
  </form>
</body></html>]])
assert(env.isAmazonClaimsVerifyPage(verify) == true)
assert(env.isAmazonEnterableOtpPage(verify) == false,
  "claims verify uses name=code, not otpCode enterable form")
assert(env.isAmazonAuthenticationChallengePage(verify) == false,
  "claims verify is enterable code, not a blocking non-OTP challenge")
assert(env.switchAuthBlockReason(verify) == "MFA")
local verifyCh = env.claimsVerifyChallengeFromHtml(verify)
assert(type(verifyCh) == "table")
assert(verifyCh.challenge:find("SMS", 1, true))
assert(env.claimsVerifyChallengeFromHtml(pollOnly) == nil)
local switchClaims = env.switchOtpChallengeFromHtml(verify)
assert(type(switchClaims) == "table")
assert(switchClaims.title == "Amazon Konto wechseln – 2FA")
local landClaims = env.finishAccountSwitchLanding(verify)
assert(landClaims.needsMfa == true)
assert(landClaims.challenge.title == "Amazon Konto wechseln – 2FA")
submitted = nil
assert(env.submitAmazonClaimsVerify(verify, "424242"))
assert(submitted:attr("action") == "verify")
assert(verify:xpath('//*[@name="code"]'):attr("value") == "424242")
submitted = nil
local switchPage, switchErr = env.submitAmazonSwitchOtp(
  mm.HTML([[<html><body>
    <form action="verify"><input name="code" type="text"/></form>
  </body></html>]]), "777888")
assert(switchErr == nil and switchPage ~= nil)
assert(submitted:attr("action") == "verify")

-- Nil connectShopForm must surface as submit error (not silent ok).
env.connectShopForm = function()
  return nil
end
local nilPage, nilErr = env.submitAmazonMfa(classic, "000111")
assert(nilPage == nil and type(nilErr) == "string" and nilErr:find("submit failed", 1, true))
local nilVerify, nilVerifyErr = env.submitAmazonClaimsVerify(verify, "000111")
assert(nilVerify == nil and type(nilVerifyErr) == "string" and nilVerifyErr:find("submit failed", 1, true))
assert(env.applyPreferredAmazonAuthDeviceSelection(nil) == "")
assert(env.applyPreferredAmazonAuthDeviceSelection(mm.HTML("<html/>"):xpath("//form")) == "")

-- Authenticator prompt fallback from raw HTML
local totpHint = mm.HTML([[<html><body>
  <form id="verification-code-form" action="/ap/cvf/approval/verifyOtp">
    <span>Open your Authenticator app</span>
    <input name="otpCode" type="text"/>
  </form>
</body></html>]])
assert(env.amazonMfaChallengePrompt(totpHint):find("Authenticator", 1, true))

local waHint = mm.HTML([[<html><body>
  <form id="verification-code-form" action="/ap/cvf/approval/verifyOtp">
    <span>Code per WhatsApp gesendet</span>
    <input name="otpCode" type="text"/>
  </form>
</body></html>]])
assert(env.amazonMfaChallengePrompt(waHint):find("WhatsApp", 1, true))
local waHintLower = mm.HTML([[<html><body>
  <form id="verification-code-form">
    <span>code via whatsapp</span>
    <input name="otpCode" type="text"/>
  </form>
</body></html>]])
assert(env.amazonMfaChallengePrompt(waHintLower):find("WhatsApp", 1, true))

-- VOICE preferred over unknown device suffix
assert(env.amazonAuthDeviceChannelScore("a.VOICE")
  > env.amazonAuthDeviceChannelScore("a.OTHER"))

print("test_amazon_2fa_methods OK")
