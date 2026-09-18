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

-- 把 ccal 原始月头 "丙午年七月小13日始" 格式化为 "农历丙午年七月小"
local function formatLunarMonthHeader(header)
	if type(header) ~= "string" then
		return ""
	end
	local base = header:match("^(.-)%d+日始$")
	if not base or base == "" then
		return header
	end
	return "农历" .. base
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
					fontWeight = "semibold",
					color = "on_surface_variant",
					textAlign = "center",
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
	-- 显式给每个格子一个填充值（非今天为透明）：reconciler 对缺失的 fill
	-- 不会清除旧值，fill = nil 会导致昨天的高亮背景残留。
	local fill = "primary/0"
	local holidayBadge = ""

	if isToday then
		fill = "primary/0.15"
		dayColor = "primary"
		lunarColor = "primary"
	elseif hasEvents then
		dayColor = "error"
		lunarColor = "error"
	elseif highlightHolidays and type(holiday) == "table" then
		if holiday.isHoliday then
			holidayBadge = "休"
			dayColor = "error"
			lunarColor = "error"
		elseif holiday.isWorkday then
			holidayBadge = "补班"
			dayColor = "tertiary"
			lunarColor = "tertiary"
		end
	end

	-- 固定 label 槽位，数量与顺序恒定：日期/农历/休补班/节气/事件。
	-- 不存在的内容用空字符串占位，保证每次 render 子节点数一致，
	-- 否则 reconcile 按位置复用旧节点时无法清理残留样式。
	local content = {
		ui.label({
			text = gregorianText,
			fontSize = isToday and 22 or 18,
			fontWeight = isToday and "bold" or "medium",
			color = dayColor,
			textAlign = "center",
		}),
		-- 农历槽位：无农历数据时为空串
		ui.label({
			text = lunarText,
			fontSize = 11,
			color = lunarColor,
			textAlign = "center",
		}),
		-- 节假日徽标槽位：休日显示"休"，调休上班显示"补班"，其余为空串
		ui.label({
			text = holidayBadge,
			fontSize = 10,
			fontWeight = "bold",
			color = holidayBadge == "休" and "#00C853" or "tertiary",
			textAlign = "center",
		}),
		-- 节气槽位：无节气或关闭显示时为空串
		ui.label({
			text = showSolarTerm and solarTerm or "",
			fontSize = 10,
			fontWeight = "medium",
			color = "secondary",
			textAlign = "center",
		}),
		-- 自定义事件槽位：无事件时为空串，多条事件合并为单个槽位
		ui.label({
			text = #eventDescs > 0 and table.concat(eventDescs, " ") or "",
			fontSize = 10,
			fontWeight = "medium",
			color = "secondary",
			textAlign = "center",
		}),
	}

	return ui.column({
		key = string.format("day-%d-%02d-%02d", year, month, day),
		gap = 2,
		align = "center",
		justify = "center",
		padding = 8,
		fill = fill,
		radius = 8,
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

	-- 显示当日完整日期：2026年8月4日 星期二
	local fullDateText = string.format("%d年%d月%d日 星期%s", date.year, date.month, date.day, WEEKDAYS[date.wday])

	local cache = lunarDataCache[monthKey(year, month)]
	local lunarHeader = ""
	if type(cache) == "table" and type(cache.monthInfo) == "table" and cache.monthInfo.header then
		lunarHeader = formatLunarMonthHeader(cache.monthInfo.header)
	end

	return ui.column({ gap = 6, align = "center" }, {
		ui.label({
			text = fullDateText,
			fontSize = 18,
			fontWeight = "bold",
			color = "primary",
		}),
		ui.label({
			text = lunarHeader,
			fontSize = 13,
			color = "secondary",
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
