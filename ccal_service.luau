-- 中国农历后台服务。
--
-- 这个 headless entry 负责耗时工作：检查 ccal、执行命令、解析 XML、
-- 拉取 holiday-cn 数据，并把 plain state 发布给 bar widget。

local lunarDataCache = {}
local holidayCache = {}
local dataVersion = 0
local holidayDataVersion = 0
local ccalAvailable = nil

local loadMonthData
local loadHolidayDataForYear
local handleCommand

local chineseDays = {
	[1] = "初一",
	[2] = "初二",
	[3] = "初三",
	[4] = "初四",
	[5] = "初五",
	[6] = "初六",
	[7] = "初七",
	[8] = "初八",
	[9] = "初九",
	[10] = "初十",
	[11] = "十一",
	[12] = "十二",
	[13] = "十三",
	[14] = "十四",
	[15] = "十五",
	[16] = "十六",
	[17] = "十七",
	[18] = "十八",
	[19] = "十九",
	[20] = "二十",
	[21] = "廿一",
	[22] = "廿二",
	[23] = "廿三",
	[24] = "廿四",
	[25] = "廿五",
	[26] = "廿六",
	[27] = "廿七",
	[28] = "廿八",
	[29] = "廿九",
	[30] = "三十",
}

local lunarMonthNumbers = {
	["正月"] = 1,
	["二月"] = 2,
	["三月"] = 3,
	["四月"] = 4,
	["五月"] = 5,
	["六月"] = 6,
	["七月"] = 7,
	["八月"] = 8,
	["九月"] = 9,
	["十月"] = 10,
	["十一月"] = 11,
	["十二月"] = 12,
}

local function lunarMonthNumber(name)
	return lunarMonthNumbers[name]
end

local function pad2(value)
	return string.format("%02d", tonumber(value) or 0)
end

local function monthKey(year, month)
	return `{year}-{pad2(month)}`
end

local function cfgInt(key, fallback, minValue, maxValue)
	local value = tonumber(noctalia.getConfig(key)) or fallback
	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

local function cfgBool(key, fallback)
	local value = noctalia.getConfig(key)
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function currentYearMonth()
	local now = os.date("*t")
	return now.year, now.month
end

local function publishAvailability(value)
	ccalAvailable = value
	noctalia.state.set("ccalAvailable", value)
end

local function publishLunarData()
	dataVersion += 1
	noctalia.state.set("lunarDataCache", lunarDataCache)
	noctalia.state.set("dataVersion", dataVersion)
end

local function publishHolidayData()
	holidayDataVersion += 1
	noctalia.state.set("holidayCache", holidayCache)
	noctalia.state.set("holidayDataVersion", holidayDataVersion)
end

local function parseCcalOutput(key, output)
	local monthData = {
		days = {},
		monthInfo = {},
	}

	local header = output:match('<ccal:month[^>]+cname="([^"]+)"')
	if header then
		monthData.monthInfo.header = header
	end

	for gregDay, leap, lunarDayNum, lunarMonthName, displayName in
		output:gmatch(
			'<ccal:day%s+value="(%d+)"[^>]*leap="([^"]*)"[^>]*cdate="(%d+)"[^>]*cmonthname="([^"]+)"[^>]*cdatename="([^"]+)"'
		)
	do
		local lunarDayText = chineseDays[tonumber(lunarDayNum)] or displayName
		local isLeap = leap ~= nil and leap ~= ""
		local fullLunarDate = `{if isLeap then "闰" else ""}{lunarMonthName}{lunarDayText}`

		local solarTerm = ""
		if displayName ~= lunarDayText and displayName ~= lunarMonthName and not displayName:find("月", 1, true) then
			solarTerm = displayName
		end

		monthData.days[gregDay] = {
			lunarDay = displayName,
			lunarDayRaw = lunarDayText,
			lunarDayNum = tonumber(lunarDayNum),
			lunarMonthName = lunarMonthName,
			lunarMonthNum = lunarMonthNumber(lunarMonthName),
			fullLunarDate = fullLunarDate,
			solarTerm = solarTerm,
			isLeap = isLeap,
		}
	end

	lunarDataCache[key] = monthData
	publishLunarData()
	noctalia.log(`[ccal] loaded lunar data for {key}`)
end

loadMonthData = function(year, month, force)
	year = tonumber(year)
	month = tonumber(month)

	if year == nil or month == nil or month < 1 or month > 12 then
		noctalia.log("[ccal] ignored invalid month request")
		return
	end

	if ccalAvailable ~= true then
		return
	end

	local key = monthKey(year, month)
	if not force and lunarDataCache[key] ~= nil then
		return
	end

	local command = `ccal -x -g -u {month} {year}`
	local started = noctalia.runAsync(command, function(result)
		if result.exitCode == 0 then
			parseCcalOutput(key, result.stdout or "")
		else
			noctalia.log(`[ccal] command failed for {key}: exit {tostring(result.exitCode)}`)
		end
	end)

	if not started then
		noctalia.log(`[ccal] failed to start command for {key}`)
	end
end

local function processHolidayDays(yearKey, days)
	local processed = {}

	for _, day in ipairs(days) do
		if type(day) == "table" and type(day.date) == "string" then
			processed[day.date] = {
				name = day.name or "",
				isHoliday = day.isOffDay == true,
				isWorkday = day.isOffDay == false,
			}
		end
	end

	holidayCache[yearKey] = processed
	publishHolidayData()
	noctalia.log(`[ccal] loaded holiday data for {yearKey}`)
end

loadHolidayDataForYear = function(year, force)
	if not cfgBool("fetch_holidays", true) then
		return
	end

	year = tonumber(year)
	if year == nil then
		return
	end

	local yearKey = tostring(year)
	if not force and holidayCache[yearKey] ~= nil then
		return
	end

	local url = `https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json`
	noctalia.http({ url = url }, function(res)
		if not res.ok then
			noctalia.log(`[ccal] failed to fetch holiday data for {yearKey}`)
			return
		end

		local data, err = noctalia.json.decode(res.body)
		if type(data) ~= "table" or type(data.days) ~= "table" then
			noctalia.log(`[ccal] failed to parse holiday data for {yearKey}: {tostring(err)}`)
			return
		end

		processHolidayDays(yearKey, data.days)
	end)
end

local function refreshCurrentData(force)
	local year, month = currentYearMonth()
	loadMonthData(year, month, force)

	if cfgBool("fetch_holidays", true) then
		loadHolidayDataForYear(year, force)
	end
end

local function checkCcalAvailability(force)
	local available = noctalia.commandExists("ccal")
	publishAvailability(available)

	if available then
		refreshCurrentData(force)
	else
		noctalia.log("[ccal] ccal command not found")
	end
end

handleCommand = function(command)
	if type(command) ~= "table" then
		return
	end

	local action = command.action
	if action == "refresh" then
		checkCcalAvailability(true)
	elseif action == "load_month" then
		loadMonthData(command.year, command.month, true)
	elseif action == "load_holidays" then
		loadHolidayDataForYear(command.year, true)
	end
end

noctalia.setUpdateInterval(cfgInt("refresh_interval", 60, 15, 3600) * 1000)
noctalia.state.watch("command", handleCommand)
checkCcalAvailability(false)

function update()
	if ccalAvailable ~= true then
		checkCcalAvailability(false)
		return
	end

	refreshCurrentData(false)
end

function onIpc(event, payload)
	if event == "refresh" then
		checkCcalAvailability(true)
	elseif event == "load_month" and type(payload) == "table" then
		loadMonthData(payload.year, payload.month, true)
	elseif event == "load_holidays" and type(payload) == "table" then
		loadHolidayDataForYear(payload.year, true)
	end
end
