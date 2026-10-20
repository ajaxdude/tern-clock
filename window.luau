-- Clock: the system time in Tern's tab bar, 12h/24h, positioned left, centered,
-- beside the window buttons, or in the status line. Settings persist in kv and
-- apply live in every window.

local ID = "clock"
local DEFAULT_FMT = "24h"
local DEFAULT_PLACE = "center"
local PLACES = { "center", "left", "right", "status" }
local PLACE_TITLES = {
	center = "Centered in the tab bar",
	left = "Far left of the tab bar",
	right = "Beside the window buttons",
	status = "In the status line",
}
local FMT_TITLES = { ["24h"] = "24-hour (15:42)", ["12h"] = "12-hour (3:42 pm)" }

-- Anchors for turning the monotonic clock into sub-second wall time.
local anchor_sec = os.time()
local anchor_ms = tern.now()

local function get_cfg()
	return {
		fmt = tern.kv.get("fmt") or DEFAULT_FMT,
		place = tern.kv.get("place") or DEFAULT_PLACE,
		seconds = tern.kv.get("seconds") == true,
	}
end

local function clock_text(cfg)
	local s
	if cfg.fmt == "12h" then
		s = os.date(cfg.seconds and "%I:%M:%S %p" or "%I:%M %p")
		s = (s:gsub("^0", ""))
		s = (s:gsub("([AP])M", function(c) return c:lower() .. "m" end))
	else
		s = os.date(cfg.seconds and "%H:%M:%S" or "%H:%M")
	end
	return s
end

-- A generous width for the lifted segment: 12.5px tabular digits plus the icon,
-- padding and slack; CSS divides by --tn-zoom, so this is zoom-1 pixels.
local function css_text(place, text)
	local w = math.ceil(#text * 7.8 + 40)
	local seg = ".sl-plugin[data-plugin=\"" .. ID .. "\"]"
	local sheet = { seg .. [[ {
	position: fixed;
	z-index: 31;
	top: calc((var(--tn-bar, 40px) - 17px * var(--tn-zoom, 1)) / 2);
	display: inline-flex;
	align-items: center;
	gap: 5px;
	padding: 1px 8px;
	border-radius: 7px;
	font-size: calc(12.5px * var(--tn-zoom, 1));
	font-weight: 500;
	font-variant-numeric: tabular-nums;
	color: var(--t2);
	white-space: nowrap;
	-webkit-app-region: no-drag;
}
]] .. seg .. [[ .ico {
	width: 12px;
	height: 12px;
	opacity: 0.75;
	flex: none;
}
]] .. seg .. [[:hover {
	color: var(--t1);
	background: rgb(127 127 127 / 14%);
}
]] }

	if place == "center" then
		table.insert(sheet, seg .. [[ {
	left: 50%;
	transform: translateX(-50%);
}
]])
	elseif place == "left" then
		table.insert(sheet, seg .. [[ {
	left: calc(12px / var(--tn-zoom, 1));
}
html:not(.tabs-v) #tabbar {
	padding-left: calc((20px + ]] .. w .. [[px) / var(--tn-zoom, 1));
}
html.csd-tl:not(.tabs-v) #tabbar {
	padding-left: calc((120px + ]] .. w .. [[px) / var(--tn-zoom, 1));
}
html.csd-tl ]] .. seg .. [[ {
	left: calc(108px / var(--tn-zoom, 1));
}
]])
	elseif place == "right" then
		-- The trailing cluster: Tern's window buttons (csd) when shown, plus the
		-- tools; the padding keeps tabs and buttons clear of the clock.
		table.insert(sheet, seg .. [[ {
	right: calc(200px / var(--tn-zoom, 1));
}
html:not(.tabs-v) #tabbar {
	padding-right: calc((20px + ]] .. w .. [[px) / var(--tn-zoom, 1));
}
html.csd ]] .. seg .. [[ {
	right: calc(104px / var(--tn-zoom, 1));
}
html.csd:not(.tabs-v) #tabbar {
	padding-right: calc((120px + ]] .. w .. [[px) / var(--tn-zoom, 1));
}
]])
	else -- status: leave the segment in the status line
		table.insert(sheet, seg .. [[ {
	position: static;
	top: auto;
	left: auto;
	right: auto;
	transform: none;
	font-size: inherit;
	font-weight: 400;
	padding: 0;
	border-radius: 0;
}
]])
	end

	-- Vertical tab rails have no horizontal bar to lift into.
	table.insert(sheet, "html.tabs-v " .. seg .. [[ {
	position: static;
	top: auto;
	left: auto;
	right: auto;
	transform: none;
	font-size: inherit;
	font-weight: 400;
	padding: 0;
	border-radius: 0;
}
]])
	return table.concat(sheet)
end

local applied = nil -- "place|fmt|seconds" signature of the installed CSS

local function apply_css(cfg)
	local text = clock_text(cfg)
	local sig = cfg.place .. "|" .. cfg.fmt .. "|" .. tostring(cfg.seconds)
	if sig ~= applied then
		applied = sig
		tern.css(ID, css_text(cfg.place, text))
	end
end

local function next_place(place)
	for i, p in ipairs(PLACES) do
		if p == place then
			return PLACES[i % #PLACES + 1]
		end
	end
	return DEFAULT_PLACE
end

-- One tick: keep the CSS in step with live settings and redraw the chrome.
local function tick()
	local cfg = get_cfg()
	apply_css(cfg)
	tern.chrome.refresh()
end

-- Milliseconds until the next wall-clock second (with seconds) or minute,
-- from the monotonic clock anchored to wall time at load.
local function ms_to_boundary(seconds)
	local phase = tern.now() - anchor_ms
	local sec_now = anchor_sec + math.floor(phase / 1000)
	local into_sec = math.fmod(phase, 1000)
	if seconds then
		return 1000 - into_sec + 4
	end
	local into_min = math.fmod(sec_now, 60) * 1000 + into_sec
	return 60000 - into_min + 4
end

local function schedule()
	local cfg = get_cfg()
	tern.timer(ms_to_boundary(cfg.seconds), function(_cx)
		tick()
		schedule()
	end)
end

tern.chrome.status(function(_pane)
	local cfg = get_cfg()
	return { {
		text = clock_text(cfg),
		icon = "clock",
		command = "plugin." .. ID .. ".configure",
	} }
end)

tern.command({
	id = "configure",
	title = "Clock: settings\u{2026}",
	icon = "clock",
	group = "Clock",
	run = function(cx)
		local cfg = get_cfg()
		local items = {
			{ label = FMT_TITLES["24h"], group = "Format", current = cfg.fmt == "24h", act = { fmt = "24h" } },
			{ label = FMT_TITLES["12h"], group = "Format", current = cfg.fmt == "12h", act = { fmt = "12h" } },
		}
		for _, p in ipairs(PLACES) do
			table.insert(items, { label = PLACE_TITLES[p], group = "Position", current = cfg.place == p, act = { place = p } })
		end
		table.insert(items, { label = "Seconds: off", group = "Seconds", current = not cfg.seconds, act = { seconds = false } })
		table.insert(items, { label = "Seconds: on", group = "Seconds", current = cfg.seconds, act = { seconds = true } })
		cx:pick({ items = items, placeholder = "time format and position" })
			:next(function(choice)
				if not choice then return end
				if choice.act.fmt then tern.kv.set("fmt", choice.act.fmt) end
				if choice.act.place then tern.kv.set("place", choice.act.place) end
				if choice.act.seconds ~= nil then tern.kv.set("seconds", choice.act.seconds) end
				tick()
			end)
	end,
})

tern.command({
	id = "toggle_format",
	title = "Clock: toggle 12h / 24h",
	icon = "clock",
	group = "Clock",
	run = function(_cx)
		tern.kv.set("fmt", get_cfg().fmt == "24h" and "12h" or "24h")
		tick()
	end,
})

tern.command({
	id = "cycle_place",
	title = "Clock: change position",
	icon = "clock",
	group = "Clock",
	run = function(_cx)
		tern.kv.set("place", next_place(get_cfg().place))
		tick()
	end,
})

tern.on("window_start", function(_cx)
	apply_css(get_cfg())
	schedule()
	tick()
end)
