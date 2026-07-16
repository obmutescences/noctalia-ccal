-- 中国农历桌面组件。
--
-- 显示月历视图：星期栏 + 当月日期网格，每日显示公历、农历、节气、节假日标记。
-- 复用 ccal_service.luau 发布的状态数据，无需额外请求。

local showSolarTerm = noctalia.getConfig("show_solar_term")
local highlightHolidays = noctalia.getConfig("highlight_holidays")

local ccalAvailable = noctalia.state.get("ccalAvailable")
local lunarDataCache = noctalia.state.get("lunarDataCache") or {}
local holidayCache = noctalia.state.get("holidayCache") or {}

local WEEKDAYS = { "日", "一", "二", "三", "四", "五", "六" }

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

local function getEventDescs(year, month, day, dayData)
	local descs = {}
	for _, event in ipairs(events) do
		if event.type == "G" and event.month == month and event.day == day then
			table.insert(descs, event.desc)
		elseif event.type == "L" and dayData then
			if
				event.month == dayData.lunarMonthNum
				and event.day == dayData.lunarDayNum
				and event.leap == (dayData.isLeap or false)
			then
				table.insert(descs, event.desc)
			end
		end
	end

	return descs
end

local function pad2(value)
	return string.format("%02d", tonumber(value) or 0)
end

local function monthKey(year, month)
	return `{year}-{pad2(month)}`
end

local function today()
	return os.date("*t")
end

local function daysInMonth(year, month)
	local nextMonth = month + 1
	local nextYear = year
	if nextMonth > 12 then
		nextMonth = 1
		nextYear = year + 1
	end
	local lastDay = os.time({ year = nextYear, month = nextMonth, day = 0 })
	return os.date("*t", lastDay).day
end

local function firstWeekday(year, month)
	local firstDay = os.time({ year = year, month = month, day = 1 })
	return os.date("*t", firstDay).wday
end

local function holidayInfo(year, month, day)
	local yearCache = holidayCache[tostring(year)]
	if type(yearCache) ~= "table" then
		return nil
	end
	local key = string.format("%04d-%02d-%02d", year, month, day)
	return yearCache[key]
end

local function getDayData(year, month, day)
	local cache = lunarDataCache[monthKey(year, month)]
	if type(cache) ~= "table" or type(cache.days) ~= "table" then
		return nil
	end
	return cache.days[tostring(day)]
end

local function buildWeekdayRow()
	local cells = {}
	for _, weekday in ipairs(WEEKDAYS) do
		table.insert(
			cells,
			ui.column({
				width = 70,
				align = "center",
			}, {
				ui.label({
					text = weekday,
					fontSize = 14,
					weight = "semibold",
					color = "on_surface_variant",
					align = "center",
				}),
			})
		)
	end

	return ui.row({
		gap = 4,
		justify = "center",
	}, cells)
end

local function buildDayCell(year, month, day, isToday)
	local dayData = getDayData(year, month, day)
	local holiday = holidayInfo(year, month, day)

	local gregorianText = tostring(day)
	local lunarText = dayData and dayData.lunarDayRaw or ""
	local solarTerm = dayData and dayData.solarTerm or ""

	local eventDescs = getEventDescs(year, month, day, dayData)
	local hasEvents = #eventDescs > 0

	local dayColor = "on_surface"
	local lunarColor = "on_surface_variant"
	local bgColor = nil
	local borderRadius = 8
	local showHolidayBadge = false

	if isToday then
		bgColor = "surface_variant"
		dayColor = "#00C853"
		lunarColor = "#00C853"
	elseif hasEvents then
		dayColor = "error"
		lunarColor = "error"
	elseif highlightHolidays and type(holiday) == "table" then
		if holiday.isHoliday then
			showHolidayBadge = true
			dayColor = "error"
			lunarColor = "error"
		elseif holiday.isWorkday then
			dayColor = "tertiary"
			lunarColor = "tertiary"
		end
	end

	local content = {
		ui.label({
			text = gregorianText,
			fontSize = 18,
			weight = isToday and "bold" or "medium",
			color = dayColor,
			align = "center",
		}),
	}

	if lunarText ~= "" then
		table.insert(
			content,
			ui.label({
				text = lunarText,
				fontSize = 11,
				color = lunarColor,
				align = "center",
			})
		)
	end

	-- 节假日"休"字标记 - 使用固定亮绿色
	if showHolidayBadge then
		table.insert(
			content,
			ui.label({
				text = "休",
				fontSize = 10,
				weight = "bold",
				color = "#00C853",
				align = "center",
			})
		)
	end

	if showSolarTerm and solarTerm ~= "" then
		table.insert(
			content,
			ui.label({
				text = solarTerm,
				fontSize = 10,
				weight = "medium",
				color = isToday and "#00C853" or (hasEvents and "error" or "tertiary"),
				align = "center",
			})
		)
	end

	for _, desc in ipairs(eventDescs) do
		table.insert(
			content,
			ui.label({
				text = desc,
				fontSize = 10,
				weight = "medium",
				color = "error",
				align = "center",
			})
		)
	end

	return ui.column({
		gap = 2,
		align = "center",
		justify = "center",
		padding = 8,
		bgColor = bgColor,
		borderRadius = borderRadius,
		width = 70,
		minHeight = 70,
	}, content)
end

local function buildCalendarGrid(year, month)
	local todayDate = today()
	local isCurrentMonth = todayDate.year == year and todayDate.month == month

	local totalDays = daysInMonth(year, month)
	local startWeekday = firstWeekday(year, month)

	local rows = {}
	local currentRow = {}

	-- 填充第一周的空白
	for i = 1, startWeekday - 1 do
		table.insert(currentRow, ui.column({ width = 70, minHeight = 70 }, {}))
	end

	-- 填充日期
	for day = 1, totalDays do
		local isToday = isCurrentMonth and day == todayDate.day
		table.insert(currentRow, buildDayCell(year, month, day, isToday))

		if #currentRow == 7 then
			table.insert(
				rows,
				ui.row({
					gap = 4,
					justify = "center",
				}, currentRow)
			)
			currentRow = {}
		end
	end

	-- 填充最后一周的空白
	if #currentRow > 0 then
		while #currentRow < 7 do
			table.insert(currentRow, ui.column({ width = 70, minHeight = 70 }, {}))
		end
		table.insert(
			rows,
			ui.row({
				gap = 4,
				justify = "center",
			}, currentRow)
		)
	end

	return ui.column({ gap = 4 }, rows)
end

local function buildHeader(year, month)
	local date = today()
	local monthNames = {
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

	-- 显示当日完整日期：2026年6月17日 星期二
	local fullDateText = string.format("%d年%d月%d日 星期%s", date.year, date.month, date.day, WEEKDAYS[date.wday])

	local cache = lunarDataCache[monthKey(year, month)]
	local lunarHeader = ""
	if type(cache) == "table" and type(cache.monthInfo) == "table" and cache.monthInfo.header then
		lunarHeader = cache.monthInfo.header
	end

	return ui.column({ gap = 6, align = "center" }, {
		ui.label({
			text = fullDateText,
			fontSize = 18,
			weight = "bold",
			color = "on_surface",
		}),
		ui.label({
			text = lunarHeader,
			fontSize = 13,
			color = "on_surface_variant",
		}),
	})
end

local function render()
	if ccalAvailable ~= true then
		desktopWidget.render(ui.column({ gap = 10, padding = 20, align = "center" }, {
			ui.label({
				text = "未安装 ccal",
				fontSize = 16,
				color = "error",
			}),
			ui.label({
				text = "请通过系统包管理器安装 ccal",
				fontSize = 12,
				color = "on_surface_variant",
			}),
		}))
		return
	end

	local date = today()
	local year = date.year
	local month = date.month

	desktopWidget.render(ui.column({
		gap = 16,
		padding = 20,
		bgColor = "surface",
		borderRadius = 16,
	}, {
		buildHeader(year, month),
		buildWeekdayRow(),
		buildCalendarGrid(year, month),
	}))
end

-- 监听状态变化
noctalia.state.watch("ccalAvailable", function(value)
	ccalAvailable = value
	render()
end)

noctalia.state.watch("lunarDataCache", function(value)
	lunarDataCache = value or {}
	render()
end)

noctalia.state.watch("holidayCache", function(value)
	holidayCache = value or {}
	render()
end)

noctalia.state.watch("dataVersion", render)
noctalia.state.watch("holidayDataVersion", render)

-- 每分钟刷新一次（主要是更新"今日"高亮）
desktopWidget.setWantsSecondTicks(false)
noctalia.setUpdateInterval(60000)

function update()
	render()
end

render()
