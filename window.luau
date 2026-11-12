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

local function get_cfg()
	return {
		fmt = tern.kv.get("fmt") or DEFAULT_FMT,
		place = tern.kv.get("place") or DEFAULT_PLACE,
	}
end

local function clock_text(cfg)
	local s
	if cfg.fmt == "12h" then
		s = os.date("%I:%M %p")
		s = (s:gsub("^0", ""))
		s = (s:gsub("([AP])M", function(c) return c:lower() .. "m" end))
	else
		s = os.date("%H:%M")
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

local applied = nil -- "place|fmt" signature of the installed CSS

local function apply_css(cfg)
	local text = clock_text(cfg)
	local sig = cfg.place .. "|" .. cfg.fmt
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

-- Redraws fire just after each wall-clock minute boundary. os.time() floors
-- to whole seconds,
-- so the sub-second phase comes from tern.now(), the VM's monotonic clock.
-- That clock and the OS wall clock share no common origin, so the offset
-- between them is not assumed, it is measured: a firing whose scheduled
-- whole second had not yet appeared in os.time() proves the phase estimate
-- ran hot, so the estimate is shifted later; a firing that landed on its
-- second nudges it back earlier. The estimate converges within a few
-- firings and NTP slew or steps, a suspended VM, or a throttled timer are
-- absorbed the same way instead of accumulating. The text itself is drawn
-- from the wall clock, so a firing delayed by a stalled event loop can only
-- make it lag, never run ahead.
local schedule -- forward
local timer = nil -- the pending redraw timer
local gen = 0 -- schedule generation; a new one supersedes a fired chain

local PERIOD = 60000 -- repaint cadence: once per wall-clock minute

local bias_ms = 0 -- learned offset aligning the monotonic phase to the wall clock
local cfg_cache = nil -- last settings read; the status hook must not cross the
                      -- plugin boundary (kv reads are native and budgeted at 40 ms)
local last_fire = os.time() -- when the redraw chain was last known alive

local function wall_ms()
	local frac = math.fmod(tern.now() * 1000 - bias_ms, 1000)
	if frac < 0 then
		frac += 1000
	end
	return os.time() * 1000 + frac
end

-- One tick: keep CSS and settings in step with the kv and redraw.
local function tick()
	local cfg = get_cfg()
	cfg_cache = cfg
	last_fire = os.time()
	apply_css(cfg)
	tern.chrome.refresh()
end

schedule = function()
	gen += 1
	local my_gen = gen
	if timer then
		timer:cancel() -- no effect once it has fired
	end
	timer = nil
	last_fire = os.time()
	local now = wall_ms()
	local wait = PERIOD - math.fmod(now, PERIOD) -- in (0, PERIOD]
	local target = math.floor((now + wait) / 1000) -- whole wall second this firing aims at
	local handle
	handle = tern.timer(wait + 16, function(_cx) -- +16 ms: land past the boundary
		local ok, err = pcall(tick)
		if not ok then
			tern.log.warn("clock: redraw failed: " .. tostring(err))
		end
		if gen ~= my_gen then
			return -- tick re-armed for a new cadence; the new chain owns the state
		end
		local landed = os.time()
		if landed < target then
			bias_ms += 512 -- fired before the real boundary: estimate ran hot
		elseif landed == target then
			-- The firing is on target, so the sub-second part of the aligned
			-- estimate is the latency the event loop cost this time. Cancel
			-- most of it from the next firing, so updates keep landing a hair
			-- after the boundary instead of drifting deeper into the minute.
			local lag = math.fmod(wall_ms(), 1000) - 16
			if lag > 0 then
				bias_ms -= lag * 3 / 4
			end
		end
		if timer == handle then
			timer = nil
		end
		schedule()
	end)
	timer = handle
end

tern.chrome.status(function(_pane)
	local cfg = cfg_cache or get_cfg()
	if os.time() - last_fire > 62 then
		-- The renderer can revoke a plugin hook for running over budget, which
		-- kills whatever the callback was doing — including its re-arm. Any
		-- repaint is a chance to notice the chain stopped and start it again.
		schedule()
	end
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
		cx:pick({ items = items, placeholder = "time format and position" })
			:next(function(choice)
				if not choice then return end
				if choice.act.fmt then tern.kv.set("fmt", choice.act.fmt) end
				if choice.act.place then tern.kv.set("place", choice.act.place) end
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

-- The clock is a status-line segment; its host must exist (the placement CSS
-- lifts it out of the bottom bar into the tab bar).
tern.on("window_start", function(cx)
	if not cx.settings:get("status_bar") then
		cx.settings:set("status_bar", true)
	end
	local ok, err = pcall(tick) -- installs the CSS
	if not ok then
		tern.log.warn("clock: start failed: " .. tostring(err))
	end
	schedule() -- arms the redraw chain
end)

-- A plugin reload replaces the module but runs no window_start, so the chain
-- has to arm here too: otherwise a reloaded clock renders once and freezes.
local ok_arm, err_arm = pcall(schedule)
if not ok_arm then
	tern.log.warn("clock: arm failed: " .. tostring(err_arm))
end
