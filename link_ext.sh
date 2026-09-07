#!/bin/sh
ls -li ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-bestellungen.lua amazon-bestellungen.lua

rm -f ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-bestellungen.lua
ln amazon-bestellungen.lua ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-bestellungen.lua

ls -li ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-bestellungen.lua amazon-bestellungen.lua
