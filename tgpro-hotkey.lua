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
    { type = "temperature", name = "Performance", configSensor = 0, configFan = 0, curve = {
        { temperatureLimit = 30, percent = 0 },
        { temperatureLimit = 40, percent = 0 },
        { temperatureLimit = 50, percent = 25 },
        { temperatureLimit = 60, percent = 60 },
        { temperatureLimit = 70, percent = 75 },
        { temperatureLimit = 80, percent = 90 },
        { temperatureLimit = 90, percent = 100 },
    } },
    { type = "temperature", name = "Turbo", configSensor = 0, configFan = 0, curve = {
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
local applyInProgress = false  -- 防抖：apply 期间忽略新按键

local function readTemp()
  local f = io.popen(READTEMP_BIN .. " 2>/dev/null")
  if not f then return nil end
  local out = f:read("*a"); f:close()
  return tonumber((out or ""):match("[%d%.]+"))
end

local function alert(text)
  if cfg.alertEnabled then hs.alert.show(text, cfg.alertDuration) end
end

-- 兜底：万一 hs.task 回调因为子进程异常没触发，5 秒后强制清防抖标志
local function setApplyInProgress(running)
  applyInProgress = running
  if running then
    hs.timer.doAfter(5, function() applyInProgress = false end)
  end
end

-- 异步把规则数组喂给 tgpro-rules（同步会阻塞 Hammerspoon 1-2 秒）
local function applyRules(rules)
  setApplyInProgress(true)
  local body = hs.json.encode({ rules = rules or {} })
  local task = hs.task.new(TGPRO_BIN, function() setApplyInProgress(false) end, { "apply" })
  if not task then setApplyInProgress(false); return end
  task:setInput(body)
  task:start()
end

local function clearRules()
  setApplyInProgress(true)
  local task = hs.task.new(TGPRO_BIN, function() setApplyInProgress(false) end, { "clear" })
  if not task then setApplyInProgress(false); return end
  task:start()
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
  applyRules({ { percent = 100, temperatureLimit = 0, configSensor = 0, configFan = 0 } })
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
        configSensor = step.configSensor or 0,  -- Any Sensor
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
    applyRules({ { percent = 100, temperatureLimit = 0, configSensor = 0, configFan = 0 } })
    scheduleAutoRevert(step)
    alert(effectiveName(step))
  elseif t == "cooldown" then
    startCooldown(step)
  elseif t == "temperature" then
    applyTemperature(step)
  end
end

local function cycle()
  if applyInProgress then return end  -- 防抖
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

-- 启动时弹一下当前默认档位（cycleIndex 起点 = 1）
if cfg.cycleSteps and cfg.cycleSteps[cycleIndex] then
  hs.timer.doAfter(0.5, function()
    alert(effectiveName(cfg.cycleSteps[cycleIndex]))
  end)
end

return M
