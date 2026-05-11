-- ===== tgpro-hotkey-mac =====
-- 按用户自定义的「档位列表」循环切换 TG Pro 的 Auto Max Rules
-- https://github.com/KrisWonka/tgpro-hotkey-mac

local M = {}

local HS_DIR = os.getenv("HOME") .. "/.hammerspoon"
local CONFIG_PATH = HS_DIR .. "/tgpro-hotkey-config.json"
local READTEMP_BIN = HS_DIR .. "/readtemp"
local TGPRO_BIN    = HS_DIR .. "/tgpro-rules"

-- 默认配置（被 tgpro-hotkey-config.json 覆盖；JSON 是 FanHotkey.app 写的）
local cfg = {
  hotkeyEnabled = true,
  hotkeyMods = { "ctrl", "alt", "cmd" },
  hotkeyKey = "8",
  alertEnabled = true,
  alertCooldownDone = "Cooldown done ✓",
  alertDuration = 1.2,
  -- 默认 3 档：Silence (Auto) / Performance / Turbo（GUI 第一次保存会覆盖此 JSON）
  cycleSteps = {
    { type = "auto", name = "Silence" },
    { type = "temperature", name = "Performance", configSensor = 4, configFan = 0, curve = {
        { temperatureLimit = 30, percent = 0 },
        { temperatureLimit = 40, percent = 0 },
        { temperatureLimit = 50, percent = 25 },
        { temperatureLimit = 60, percent = 60 },
        { temperatureLimit = 70, percent = 75 },
        { temperatureLimit = 80, percent = 90 },
        { temperatureLimit = 90, percent = 100 },
    } },
    { type = "temperature", name = "Turbo", configSensor = 4, configFan = 0, curve = {
        { temperatureLimit = 20, percent = 0 },
        { temperatureLimit = 30, percent = 0 },
        { temperatureLimit = 45, percent = 0 },
        { temperatureLimit = 50, percent = 35 },
        { temperatureLimit = 60, percent = 95 },
        { temperatureLimit = 70, percent = 100 },
        { temperatureLimit = 80, percent = 100 },
        { temperatureLimit = 90, percent = 100 },
    } },
  },
}

local function loadConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, parsed = pcall(hs.json.decode, raw)
  if not ok or type(parsed) ~= "table" then return end
  for k, v in pairs(parsed) do cfg[k] = v end
end
loadConfig()

local autoRevertTimer = nil
local cooldownTimer   = nil
-- 起点假设为列表第 1 档（Silence / Auto = Mac 默认状态），按一下进第 2 档
local cycleIndex      = 1

local function readTemp()
  local f = io.popen(READTEMP_BIN .. " 2>/dev/null")
  if not f then return nil end
  local out = f:read("*a"); f:close()
  return tonumber((out or ""):match("[%d%.]+"))
end

local function alert(text)
  hs.alert.closeAll(0)  -- 先把现有 alert 立刻关掉，避免连按时堆成一列
  if cfg.alertEnabled then hs.alert.show(text, cfg.alertDuration) end
end

-- shell 转义：单引号包裹 + 内部单引号转义
local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Fire-and-forget 把规则喂给 tgpro-rules
-- 写到临时文件再 cat 进去，避免每次 stdin pipe 的麻烦
local function applyRules(rules)
  local body = hs.json.encode({ rules = rules or {} })
  local tmp = os.tmpname()
  local f = io.open(tmp, "w"); if not f then return end
  f:write(body); f:close()
  os.execute(string.format("(/bin/cat %s | %s apply >/dev/null 2>&1; /bin/rm -f %s) &",
    shellQuote(tmp), shellQuote(TGPRO_BIN), shellQuote(tmp)))
end

local function clearRules()
  os.execute(string.format("(%s clear >/dev/null 2>&1) &", shellQuote(TGPRO_BIN)))
end

local function defaultName(t)
  if t == "auto"        then return "Auto"
  elseif t == "fullBlast"   then return "Full Blast"
  elseif t == "cooldown"    then return "Cooldown"
  elseif t == "temperature" then return "Temperature"
  end
  return t or "?"
end

local function effectiveName(step)
  local n = step.name
  if type(n) == "string" then
    n = n:gsub("^%s*(.-)%s*$", "%1")
    if #n > 0 then return n end
  end
  return defaultName(step.type)
end

local function cancelAutoRevert()
  if autoRevertTimer then autoRevertTimer:stop(); autoRevertTimer = nil end
end

local function cancelCooldown()
  if cooldownTimer then cooldownTimer:stop(); cooldownTimer = nil end
end

local function scheduleAutoRevert(step)
  cancelAutoRevert()
  if not step.autoRevertEnabled then return end
  local sec = step.autoRevertSec or 600
  autoRevertTimer = hs.timer.doAfter(sec, function()
    autoRevertTimer = nil
    clearRules()
    alert(defaultName("auto") .. " ⏱")
  end)
end

local function startCooldown(step)
  cancelCooldown()
  applyRules({ { percent = 100, temperatureLimit = 0, configSensor = 4, configFan = 0 } })
  alert(effectiveName(step))
  local target = step.cooldownTargetTemp or 40
  local poll   = step.cooldownPollSec or 3
  cooldownTimer = hs.timer.doEvery(poll, function()
    local t = readTemp()
    if t and t < target then
      cancelCooldown()
      clearRules()
      alert(cfg.alertCooldownDone)
    end
  end)
end

local function applyTemperature(step)
  local rules = {}
  for _, p in ipairs(step.curve or {}) do
    -- percent < 0 = "Stop" 档，跳过不写规则（让系统 Auto 决定，风扇可停）
    if (p.percent or 0) >= 0 then
      table.insert(rules, {
        percent = p.percent,
        temperatureLimit = p.temperatureLimit or 0,
        configSensor = step.configSensor or 4,  -- 4 = Highest CPU
        configFan = step.configFan or 0,        -- All Fans
      })
    end
  end
  applyRules(rules)
  alert(effectiveName(step))
end

local function applyStep(step)
  cancelAutoRevert()
  cancelCooldown()
  local t = step and step.type
  if t == "auto" then
    clearRules()
    alert(effectiveName(step))
  elseif t == "fullBlast" then
    applyRules({ { percent = 100, temperatureLimit = 0, configSensor = 4, configFan = 0 } })
    scheduleAutoRevert(step)
    alert(effectiveName(step))
  elseif t == "cooldown" then
    startCooldown(step)
  elseif t == "temperature" then
    applyTemperature(step)
  end
end

local function cycle()
  local steps = cfg.cycleSteps or {}
  if #steps == 0 then
    alert("循环列表为空")
    return
  end
  cycleIndex = cycleIndex % #steps + 1
  applyStep(steps[cycleIndex])
end

if cfg.hotkeyEnabled and cfg.hotkeyKey and #cfg.hotkeyMods > 0 then
  hs.hotkey.bind(cfg.hotkeyMods, cfg.hotkeyKey, cycle)
end

-- ===== 菜单栏自定义图标 =====
-- 仿 TG Pro 风格：两行小字
--   第 1 行: 档位名         当前温度
--   第 2 行: Fans Off       (无 SMC 访问权限拿不到 RPM)
local statusBar = hs.menubar.new(true, "tgproHotkeyIndicator")

-- 通过查 iStat Menus 的 history.db 拿风扇 RPM
-- iStat Menus 7 把所有 sensor 历史写在 ~/Library/Application Support/iStat Menus 7/history/history.db
-- 风扇 RPM 是几个 key，value 在 1500-8500 范围。取最近的 5 秒间隔行。
-- 注：iStat 每 ~60s 才落盘一次，所以 RPM 数字会有最多 ~60s 延迟
local ISTAT_DB = os.getenv("HOME") .. "/Library/Application Support/iStat Menus 7/history/history.db"

local function readFanRPMs()
  local f = io.open(ISTAT_DB, "r"); if not f then return nil end; f:close()
  local cmd = string.format(
    [[/usr/bin/sqlite3 -readonly %q "SELECT key, value FROM sensors WHERE interval=5 AND value BETWEEN 1500 AND 8500 AND time > strftime('%%s','now')-300 ORDER BY time DESC, value DESC LIMIT 4" 2>/dev/null]],
    ISTAT_DB
  )
  local h = io.popen(cmd); if not h then return nil end
  local out = h:read("*a"); h:close()
  -- 同 key 只保留最新一条；按 value 降序拿前 2 个 = 假设是「当前实际转速」
  local seen, rpms = {}, {}
  for k, v in (out or ""):gmatch("(%d+)|([%d%.]+)") do
    if not seen[k] then
      seen[k] = true
      table.insert(rpms, tonumber(v))
    end
  end
  if #rpms == 0 then return nil end
  table.sort(rpms, function(a,b) return a > b end)
  return rpms  -- 已按降序排，rpms[1] 是最快
end

local function fmtTitle()
  local step = cfg.cycleSteps[cycleIndex] or {}
  local mode = effectiveName(step)
  local t = readTemp()
  local tempStr = t and string.format("%d°C", math.floor(t + 0.5)) or "—°C"
  local line1 = string.format("%s  %s", mode, tempStr)
  local rpms = readFanRPMs()
  local line2
  if rpms and #rpms > 0 then
    line2 = string.format("%d RPM", math.floor(rpms[1] + 0.5))
  else
    line2 = "Fans —"
  end
  return hs.styledtext.new(line1 .. "\n" .. line2, {
    font = { name = "Menlo", size = 9 },
    paragraphStyle = { alignment = "right", lineSpacing = -2 },
  })
end

local function refreshStatusBar()
  if not statusBar then return end
  statusBar:setTitle(fmtTitle())
end

if statusBar then
  statusBar:setClickCallback(function() cycle() end)
  -- 右键菜单：直接选档位，不用循环
  local function buildMenu()
    local items = {}
    for i, s in ipairs(cfg.cycleSteps or {}) do
      table.insert(items, {
        title = string.format("%s%s", i == cycleIndex and "● " or "   ", effectiveName(s)),
        fn = function()
          cycleIndex = ((i - 1) % #cfg.cycleSteps + #cfg.cycleSteps) % #cfg.cycleSteps
          cycle()  -- cycle() 会 +1
        end,
      })
    end
    table.insert(items, { title = "-" })
    table.insert(items, { title = "打开 TG Hotkey 配置…", fn = function() hs.execute("/usr/bin/open -a 'TG Hotkey'") end })
    table.insert(items, { title = "打开 TG Pro 主窗…", fn = function() hs.execute("/usr/bin/open -a 'TG Pro'") end })
    return items
  end
  statusBar:setMenu(buildMenu)
  refreshStatusBar()
  -- 每 2 秒刷新温度显示
  hs.timer.doEvery(2, refreshStatusBar)
end

-- 启动时弹一下当前默认档位（cycleIndex 起点 = 1）
if cfg.cycleSteps and cfg.cycleSteps[cycleIndex] then
  hs.timer.doAfter(0.5, function()
    alert(effectiveName(cfg.cycleSteps[cycleIndex]))
  end)
end

-- cycle 后立刻刷新状态栏
local _origCycle = cycle
cycle = function()
  _origCycle()
  refreshStatusBar()
end
if cfg.hotkeyEnabled and cfg.hotkeyKey and #cfg.hotkeyMods > 0 then
  hs.hotkey.deleteAll(cfg.hotkeyMods, cfg.hotkeyKey)
  hs.hotkey.bind(cfg.hotkeyMods, cfg.hotkeyKey, cycle)
end

return M
