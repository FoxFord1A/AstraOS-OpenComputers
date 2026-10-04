-- AstraOS bootstrap for OpenComputers.
-- Runs directly in the Lua BIOS environment; does not depend on OpenOS libraries.
local function pauseForever()
  while true do computer.pullSignal() end
end

local function showFailure(message)
  local gpuAddress
  local iter = component.list("gpu", true)
  if iter then gpuAddress = iter() end
  if gpuAddress then
    local ok, gpu = pcall(component.proxy, gpuAddress)
    if ok and gpu then
      pcall(gpu.bind, (function()
        local screens = component.list("screen", true)
        return screens and screens()
      end)())
      local w, h = 50, 16
      pcall(function() w, h = gpu.getResolution() end)
      pcall(gpu.setBackground, 0x101820)
      pcall(gpu.setForeground, 0xFF6666)
      pcall(gpu.fill, 1, 1, w, h, " ")
      pcall(gpu.set, 2, 2, "AstraOS: ошибка загрузки")
      pcall(gpu.setForeground, 0xFFFFFF)
      pcall(gpu.set, 2, 4, tostring(message):sub(1, math.max(1, w - 2)))
      pcall(gpu.set, 2, 6, "Проверьте init.lua и /system/main.lua")
    end
  else
    pcall(computer.beep, 440, 0.5)
  end
  pauseForever()
end

local function readFile(fs, path)
  local handle, reason = fs.open(path, "r")
  if not handle then return nil, reason or "не удалось открыть файл" end
  local chunks = {}
  while true do
    local data, err = fs.read(handle, 4096)
    if data == nil then
      if err then pcall(fs.close, handle); return nil, err end
      break
    end
    chunks[#chunks + 1] = data
  end
  pcall(fs.close, handle)
  return table.concat(chunks)
end

local candidates, seen = {}, {}
local bootAddress = computer.getBootAddress and computer.getBootAddress()
if bootAddress then
  candidates[#candidates + 1] = bootAddress
  seen[bootAddress] = true
end
for address in component.list("filesystem", true) do
  if not seen[address] then
    candidates[#candidates + 1] = address
    seen[address] = true
  end
end

local bootFs, bootFsAddress
for _, address in ipairs(candidates) do
  local ok, fs = pcall(component.proxy, address)
  if ok and fs then
    local existsOk, exists = pcall(fs.exists, "/system/main.lua")
    if existsOk and exists then
      bootFs, bootFsAddress = fs, address
      break
    end
  end
end

if not bootFs then
  showFailure("не найдена /system/main.lua на доступных дисках")
end

local source, reason = readFile(bootFs, "/system/main.lua")
if not source then showFailure("/system/main.lua: " .. tostring(reason)) end
local chunk, syntaxError = load(source, "@/system/main.lua", "t", _G)
if not chunk then showFailure(syntaxError) end
local ok, runError = pcall(chunk, bootFs, bootFsAddress)
if not ok then showFailure(runError) end
-- A custom OS must keep running; returning here means the kernel exited.
pauseForever()
