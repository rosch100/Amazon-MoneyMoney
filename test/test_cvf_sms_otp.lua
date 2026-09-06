-- CVF SMS OTP smoke entry — full coverage is test_amazon_2fa_methods.lua.
-- Run: ./test/run.sh test/test_cvf_sms_otp.lua
package.path = "./test/?.lua;" .. package.path
dofile("test/test_amazon_2fa_methods.lua")
