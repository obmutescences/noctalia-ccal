-- 中国农历 bar widget。
--
-- 只负责展示：读取 ccal_service.luau 发布的状态，格式化今日日期，
-- 点击时切换弹出面板并请求刷新。

local dateFormat = noctalia.getConfig("date_format")
local refreshInterval = tonumber(noctalia.getConfig("refresh_interval")) or 60

local ccalAvailable = noctalia.state.get("ccalAvailable")
local lunarDataCache = noctalia.state.get("lunarDataCache") or {}
local holidayCache = noctalia.state.get("holidayCache") or {}

local TEXT = {
	title = "中国农历",
	loading = "农历加载中",
	notInstalled = "未安装 ccal",
}

local WEEKDAYS = { "日", "一", "二", "三", "四", "五", "六" }
local MONTH_NAMES =
	{ "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月" }
local MONTH_FULL_NAMES = {
	"一月",
	"二月",
	"三月",
	"四月",
	"五月",
	"六月",
	"七月",
	"八月",
	"九月",
	"十月",
	"十一月",
	"十二月",
}
local ZODIACS = {
	["子"] = "鼠",
	["丑"] = "牛",
	["寅"] = "虎",
	["卯"] = "兔",
	["辰"] = "龙",
	["巳"] = "蛇",
	["午"] = "马",
	["未"] = "羊",
	["申"] = "猴",
	["酉"] = "鸡",
	["戌"] = "狗",
	["亥"] = "猪",
}

local function parseEventLine(line)
	if type(line) ~= "string" then
		return false
	end
	line = noctalia.string.trim(line)
	if line == "" then
		return false
	end

	local prefix, datePart, desc = line:match("^(%a)%s+([%dL]+%-%d+)%s+(.+)$")
	if not prefix then
		return false
	end

	local leap = false
	if datePart:sub(1, 1) == "L" then
		leap = true
		datePart = datePart:sub(2)
	end

	local monthStr, dayStr = datePart:match("^(%d+)%-(%d+)$")
	local month = tonumber(monthStr)
	local day = tonumber(dayStr)
	if not month or not day then
		return false
	end

	if prefix == "G" then
		if month < 1 or month > 12 or day < 1 or day > 31 then
			return false
		end
		return true, { type = "G", month = month, day = day, desc = desc }
	elseif prefix == "L" then
		if month < 1 or month > 12 or day < 1 or day > 30 then
			return false
		end
		return true, { type = "L", month = month, day = day, desc = desc, leap = leap }
	end

	return false
end

local function parseEvents()
	local raw = noctalia.getConfig("events")
	if type(raw) ~= "table" then
		return {}
	end

	local events = {}
	for _, line in ipairs(raw) do
		local ok, event = parseEventLine(line)
		if ok then
			table.insert(events, event)
		end
	end

	return events
end

local events = parseEvents()

local function pad2(value)
	return string.format("%02d", tonumber(value) or 0)
end

local function monthKey(year, month)
	return `{year}-{pad2(month)}`
end

local function today()
	return os.date("*t")
end

local function currentDayData(date)
	local cache = lunarDataCache[monthKey(date.year, date.month)]
	if type(cache) ~= "table" or type(cache.days) ~= "table" then
		return nil, cache
	end
	return cache.days[tostring(date.day)], cache
end

local function lunarYearFromHeader(header)
	if type(header) ~= "string" then
		return ""
	end
	return header:match("^([^年]+)年") or ""
end

local function zodiacFromLunarYear(lunarYear)
	if type(lunarYear) ~= "string" or #lunarYear < 6 then
		return ""
	end
	local branch = lunarYear:sub(4, 6)
	return ZODIACS[branch] or ""
end

local function replaceTokens(format, date)
	if type(format) ~= "string" or format == "" then
		format = "ddd MM月dd日 LL"
	end

	local dayData, monthData = currentDayData(date)
	local header = monthData and monthData.monthInfo and monthData.monthInfo.header or ""
	local lunarDay = dayData and dayData.lunarDay or ""
	local lunarMonth = dayData and dayData.lunarMonthName or ""
	local lunarYear = lunarYearFromHeader(header)
	local zodiac = zodiacFromLunarYear(lunarYear)

	local replacements = {}
	local function placeholder(value)
		local index = #replacements + 1
		replacements[index] = value or ""
		return "\0" .. tostring(index) .. "\0"
	end

	local result = format

	result = result:gsub("LLLL", placeholder(header .. lunarDay))
	result = result:gsub("LLL", placeholder(lunarMonth .. lunarDay))
	result = result:gsub("LL", placeholder(lunarDay))
	result = result:gsub("LA", placeholder(zodiac))
	result = result:gsub("LY", placeholder(lunarYear))

	result = result:gsub("dddd", placeholder("星期" .. WEEKDAYS[date.wday]))
	result = result:gsub("ddd", placeholder(WEEKDAYS[date.wday]))
	result = result:gsub("MMMM", placeholder(MONTH_FULL_NAMES[date.month]))
	result = result:gsub("MMM", placeholder(MONTH_NAMES[date.month]))
	result = result:gsub("yyyy", placeholder(tostring(date.year)))
	result = result:gsub("yy", placeholder(pad2(date.year % 100)))
	result = result:gsub("MM", placeholder(pad2(date.month)))
	result = result:gsub("M", placeholder(tostring(date.month)))
	result = result:gsub("dd", placeholder(pad2(date.day)))
	result = result:gsub("d", placeholder(tostring(date.day)))

	local resultText = result:gsub("\0(%d+)\0", function(index)
		return replacements[tonumber(index)] or ""
	end)

	local eventDescs = {}
	for _, event in ipairs(events) do
		if event.type == "G" and event.month == date.month and event.day == date.day then
			table.insert(eventDescs, event.desc)
		elseif event.type == "L" and dayData then
			if
				event.month == dayData.lunarMonthNum
				and event.day == dayData.lunarDayNum
				and event.leap == (dayData.isLeap or false)
			then
				table.insert(eventDescs, event.desc)
			end
		end
	end

	if #eventDescs > 0 then
		return resultText .. " (" .. table.concat(eventDescs, " ") .. ")"
	end

	return resultText
end

local function render()
	barWidget.setGlyph("calendar")

	if ccalAvailable == nil then
		barWidget.setGlyphColor("on_surface_variant")
		barWidget.setText(TEXT.loading)

		return
	end

	if ccalAvailable ~= true then
		barWidget.setGlyphColor("error")

		return
	end

	barWidget.setGlyphColor("primary")

	local date = today()
	local text = replaceTokens(dateFormat, date)
	if text == "" then
		text = TEXT.title
	end

	barWidget.setText(text)
end

local function applyState(key, value)
	if key == "ccalAvailable" then
		ccalAvailable = value
	elseif key == "lunarDataCache" then
		lunarDataCache = value or {}
	elseif key == "holidayCache" then
		holidayCache = value or {}
	end

	render()
end

noctalia.state.watch("ccalAvailable", function(value)
	applyState("ccalAvailable", value)
end)

noctalia.state.watch("lunarDataCache", function(value)
	applyState("lunarDataCache", value)
end)

noctalia.state.watch("holidayCache", function(value)
	applyState("holidayCache", value)
end)

noctalia.state.watch("dataVersion", render)
noctalia.state.watch("holidayDataVersion", render)

noctalia.setUpdateInterval(math.clamp(refreshInterval, 15, 3600) * 1000)

function update()
	render()
end

function onClick()
	noctalia.togglePanel("noctalia/ccal:calendar_panel")
	noctalia.state.set("command", { action = "refresh", requestId = os.clock() })
end

function onIpc(event, payload)
	if event == "set_format" and type(payload) == "string" then
		dateFormat = payload
		render()
	elseif event == "refresh" then
		noctalia.state.set("command", { action = "refresh", requestId = os.clock() })
	end
end

render()
