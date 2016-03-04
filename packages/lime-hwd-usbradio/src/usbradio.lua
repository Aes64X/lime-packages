#!/usr/bin/lua

local utils = require("lime.utils")
local config = require("lime.config")
local hardware_detection = require("lime.hardware_detection")

local libuci = require("uci")
local fs = require("nixio.fs")

usbradio = {}

usbradio.sectionNamePrefix = hardware_detection.sectionNamePrefix.."usbradio_"

--! Remove configuration about no more plugged usb radio
function usbradio.clean()
	local uci = libuci:cursor()

	--! This function control if a usb radio configuration section is valid otherwise delete it 
	local function test_and_clean_device(s)
		--! Check if passed section is an usb radio
		local sectionName = s[".name"]
		if utils.stringStarts(sectionName, usbradio.sectionNamePrefix) then
			--! Check if the section is autogenerated otherwise do not touch it
			--! We check it to avoid delete usb radio sections manually configured 
			if config.get_bool(sectionName, "autogenerated") then
				local phyIndex = sectionName:match("%d+$")
				--! Check if the usb radio exist
				--! If the usb radio does not exist anymore (numberOfMatches < 1) delete it
				local _, numberOfMatches = fs.glob("/sys/devices/"..s["path"].."/ieee80211/phy"..phyIndex)
				if numberOfMatches < 1 then
					local radioName = s["radio_name"]
					uci:delete("wireless", radioName)
					config.delete(sectionName)
				end
			end
		end
	end

	--! For each wifi-device section call test_and_clean_device function 
	uci:foreach("wireless", "wifi-device", test_and_clean_device)
	uci:save("wireless")
end


--! Detect the usb radio and configurate it
function usbradio.detect_hardware()
	local stdOutput = io.popen("find /sys/devices | grep usb | grep ieee80211 | grep 'phy[0-9]*$'")
	--! Repeat for each usb radio found
	for path in stdOutput:lines() do
		--! Define useful variables
		local endBasePath, phyEnd = string.find(path, "/ieee80211/phy")
		local phyPath = string.sub(path, 14, endBasePath-1)
		local phyIndex = string.sub(path, phyEnd+1)
		local radioName = "radio"..phyIndex
		local sectionName = usbradio.sectionNamePrefix..radioName

		--! If sectionName exist and it is autogenerated configure it
		--! If sectionName does not exist it is created and configured
		--! Check if a sectionName is autogenerated avoid delete usb radio introduced by the user
		if config.autogenerable(sectionName) then
			local uci = libuci:cursor()

			--! Delete the usb radio
			uci:delete("wireless", radioName)
			--! Create and configure the usb radio directly in the OpenWRT system (wireless)
			uci:set("wireless", radioName, "wifi-device")
			uci:set("wireless", radioName, "type", "mac80211")
			uci:set("wireless", radioName, "channel", "11") --TODO: working on all 802.11bgn devices; find a general way for working in different devices
			uci:set("wireless", radioName, "hwmode", "11g") --TODO: working on all 802.11gn devices; find a general way for working in different devices
			uci:set("wireless", radioName, "path", phyPath)
			uci:set("wireless", radioName, "htmode", "HT20")
			uci:set("wireless", radioName, "disabled", "0")

			uci:save("wireless")

			--! Write just once on the disk all the config.set
			config.init_batch()
			config.set(sectionName, "wifi")
			config.set(sectionName, "autogenerated", "true")
			config.set(sectionName, "radio_name", radioName)

			--! Configuration of an usb radio using general option in LiMe
			for option_name, value in pairs(config.get_all("wifi")) do
				--! Options that start with point are hidden option, we exclude them as they can cause problems
				if (option_name:sub(1,1) ~= ".") then
					--! Needed a table or a string for config.set
					if ( type(value) ~= "table" ) then value = tostring(value) end
					config.set(sectionName, option_name, value)
				end
			end
			
			local modes = {}
			for _, mode in pairs(config.get("wifi", "modes")) do
				if mode ~= "adhoc" then table.insert(modes, mode) end
			end
			config.set(sectionName, "modes", modes)

			config.end_batch()
		end
	end
end


return usbradio