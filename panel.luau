-- 中国农历面板组件。
--
-- 点击 bar widget 时弹出，显示完整月历视图：星期栏 + 当月日期网格，
-- 每日显示公历、农历、节气、节假日标记。
-- 复用 ccal_service.luau 发布的状态数据。

local showSolarTerm = noctalia.getConfig("show_solar_term")
local highlightHolidays = noctalia.getConfig("highlight_holidays")

local ccalAvailable = noctalia.state.get("ccalAvailable")
local lunarDataCache = noctalia.state.get("lunarDataCache") or {}
local holidayCache = noctalia.state.get("holidayCache") or {}

-- 面板当前浏览的年月，默认当月；点击左右按钮切换。
-- 放在文件最顶部初始化，避免热重载后模块局部变量未定义。
local viewDate = os.date("*t")
local viewYear = viewDate.year
local viewMonth = viewDate.month

-- 当前悬浮的日期（YYYY-MM-DD），在标题下方显示该日农历
local hoveredDayKey = ""

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
		return nil, cache
	end
	return cache.days[tostring(day)], cache
end

-- 从 ccal 月头取农历年，如 "丙午年七月小13日始" -> "丙午"
local function lunarYearFromHeader(header)
	if type(header) ~= "string" then
		return ""
	end
	return header:match("^([^年]+)年") or ""
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
					align = "center",
				}),
			})
		)
	end

	return ui.row({ gap = 4, justify = "center" }, cells)
end

local function buildDayCell(year, month, day, isToday)
	local dayData, cache = getDayData(year, month, day)
	local holiday = holidayInfo(year, month, day)

	local gregorianText = tostring(day)
	local lunarText = dayData and dayData.lunarDayRaw or ""
	local solarTerm = dayData and dayData.solarTerm or ""
	local eventDescs = getEventDescs(year, month, day, dayData)
	local hasEvents = #eventDescs > 0

	local dayColor = "on_surface"
	local lunarColor = "on_surface_variant"
	-- 显式给每个格子一个填充值（非今天为透明）：reconciler 对缺失的 fill
	-- 不会清除旧值，fill = nil 会导致旧高亮背景残留。
	local fill = "primary/0"
	local showHolidayBadge = false

	if isToday then
		fill = "primary/0.15"
		dayColor = "primary"
		lunarColor = "primary"
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
			fontSize = isToday and 22 or 18,
			fontWeight = isToday and "bold" or "medium",
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

	if showHolidayBadge then
		table.insert(
			content,
			ui.label({
				text = "休",
				fontSize = 10,
				fontWeight = "bold",
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
				fontWeight = "medium",
				color = "secondary",
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
				fontWeight = "medium",
				color = "secondary",
				align = "center",
			})
		)
	end

	-- 悬浮时在标题下方显示该日完整农历；用 key 区分是哪一天
	local cellProps = {
		key = `{monthKey(year, month)}-{pad2(day)}`,
		gap = 2,
		align = "center",
		justify = "center",
		padding = 8,
		fill = fill,
		radius = 8,
		width = 70,
		minHeight = 70,
		onHover = "onDayHover",
	}

	return ui.column(cellProps, content)
end

local function buildCalendarGrid(year, month)
	local todayDate = today()
	local isCurrentMonth = todayDate.year == year and todayDate.month == month

	local totalDays = daysInMonth(year, month)
	local startWeekday = firstWeekday(year, month)

	local rows = {}
	local currentRow = {}

	for i = 1, startWeekday - 1 do
		table.insert(currentRow, ui.column({ width = 70, minHeight = 70 }, {}))
	end

	for day = 1, totalDays do
		local isToday = isCurrentMonth and day == todayDate.day
		table.insert(currentRow, buildDayCell(year, month, day, isToday))

		if #currentRow == 7 then
			table.insert(rows, ui.row({ gap = 4, justify = "center" }, currentRow))
			currentRow = {}
		end
	end

	if #currentRow > 0 then
		while #currentRow < 7 do
			table.insert(currentRow, ui.column({ width = 70, minHeight = 70 }, {}))
		end
		table.insert(rows, ui.row({ gap = 4, justify = "center" }, currentRow))
	end

	return ui.column({ gap = 4 }, rows)
end

local function buildHeader(year, month)
	local date = today()

	local title = string.format("%d年%d月", year, month)
	if date.year == year and date.month == month then
		title = string.format("%d年%d月%d号", year, month, date.day)
	end

	local cache = lunarDataCache[monthKey(year, month)]
	local subtitle = ""
	if type(cache) == "table" and type(cache.monthInfo) == "table" and cache.monthInfo.header then
		subtitle = formatLunarMonthHeader(cache.monthInfo.header)
	end

	-- 悬浮日期时，副标题临时显示该日的公历 + 完整农历
	if hoveredDayKey ~= "" then
		local hYear, hMonth, hDay = hoveredDayKey:match("^(%d+)%-(%d+)%-(%d+)$")
		if hYear then
			local hoverText = string.format("%d年%d月%d日", tonumber(hYear), tonumber(hMonth), tonumber(hDay))
			local dayData = getDayData(tonumber(hYear), tonumber(hMonth), tonumber(hDay))
			if dayData then
				local lunarYear = ""
				if type(cache) == "table" and type(cache.monthInfo) == "table" then
					lunarYear = lunarYearFromHeader(cache.monthInfo.header)
				end
				hoverText = hoverText .. ` 农历{lunarYear}年{dayData.fullLunarDate or ""}`
			end
			subtitle = hoverText
		end
	end

	return ui.row({ gap = 8, align = "center", justify = "space_between" }, {
		ui.button({
			glyph = "chevron-left",
			tooltip = "上一个月",
			onClick = "onPrevMonth",
		}),
		ui.column({ gap = 6, align = "center", flexGrow = 1 }, {
			ui.label({
				text = title,
				fontSize = 18,
				fontWeight = "bold",
				color = "primary",
				align = "center",
			}),
			ui.label({
				text = subtitle,
				fontSize = 13,
				color = "secondary",
				align = "center",
			}),
		}),
		ui.button({
			glyph = "chevron-right",
			tooltip = "下一个月",
			onClick = "onNextMonth",
		}),
	})
end

local function render()
	if ccalAvailable == nil then
		panel.render(ui.column({ gap = 10, padding = 20, align = "center" }, {
			ui.label({ text = "农历加载中…", fontSize = 16, color = "on_surface_variant" }),
			ui.label({ text = "正在检查 ccal 并加载数据", fontSize = 12, color = "on_surface_variant" }),
		}))
		return
	end

	if ccalAvailable ~= true then
		panel.render(ui.column({ gap = 10, padding = 20, align = "center" }, {
			ui.label({ text = "未安装 ccal", fontSize = 16, color = "error" }),
			ui.label({ text = "请通过系统包管理器安装 ccal", fontSize = 12, color = "on_surface_variant" }),
		}))
		return
	end

	local year = viewYear
	local month = viewMonth

	panel.render(ui.column({ gap = 16, padding = 20, align = "center" }, {
		buildHeader(year, month),
		buildWeekdayRow(),
		buildCalendarGrid(year, month),
	}))
end

-- 监听状态变化（与 desktop_widget 共享同一套 service 发布的 state）
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

-- 每分钟刷新（更新"今日"高亮）
noctalia.setUpdateInterval(60000)

function onOpen(_context)
	-- 每次打开面板回到当月
	local date = today()
	viewYear = date.year
	viewMonth = date.month
	-- 打开面板时请求刷新数据
	noctalia.state.set("command", { action = "refresh", requestId = os.clock() })
	render()
end

function onClose()
	-- 面板关闭，无需清理
end

function update()
	render()
end

-- 切换上/下一个月：更新浏览状态，请求缺失的农历和节假日数据。
-- 放在文件末尾定义，保证引用的 viewYear/viewMonth/render 均已就绪。
local function navigateMonth(delta)
	local date = today()
	if type(viewYear) ~= "number" or type(viewMonth) ~= "number" then
		viewYear = date.year
		viewMonth = date.month
	end

	viewMonth = viewMonth + delta
	if viewMonth < 1 then
		viewMonth = 12
		viewYear = viewYear - 1
	elseif viewMonth > 12 then
		viewMonth = 1
		viewYear = viewYear + 1
	end
	hoveredDayKey = ""

	noctalia.log(`[ccal-panel] navigate {delta}: now viewing {viewYear}-{viewMonth}`)

	local key = monthKey(viewYear, viewMonth)
	if type(lunarDataCache[key]) ~= "table" then
		noctalia.state.set("command", {
			action = "load_month",
			year = viewYear,
			month = viewMonth,
			requestId = os.clock(),
		})
	end

	if type(holidayCache[tostring(viewYear)]) ~= "table" then
		noctalia.state.set("command", {
			action = "load_holidays",
			year = viewYear,
			requestId = os.clock(),
		})
	end

	render()
end

-- 按钮回调用全局函数名（官方推荐写法），由宿主按名字绑定
function onPrevMonth()
	navigateMonth(-1)
end

function onNextMonth()
	navigateMonth(1)
end

-- 日期格子悬浮回调：state 为 "true"/"false"，key 是该日期的 YYYY-MM-DD
function onDayHover(state, key)
	if state == "true" then
		hoveredDayKey = key or ""
	elseif hoveredDayKey == key then
		hoveredDayKey = ""
	end
	render()
end
