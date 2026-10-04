-- AstraOS BIOS bootstrap for OpenComputers.
-- Runs directly in the Lua BIOS environment; does not depend on OpenOS libraries.
local BG, FG, ACCENT, MUTED = 0x101820, 0xE6EDF3, 0x55D6BE, 0x8B98A5

local function firstComponent(kind)
  local iter = component.list(kind, true)
  local address = iter and iter()
  return address
end

local function pauseForever()
  while true do computer.pullSignal() end
end

local function showFailure(message)
  local gpuAddress = firstComponent("gpu")
  local screenAddress = firstComponent("screen")
  if gpuAddress then
    local ok, gpu = pcall(component.proxy, gpuAddress)
    if ok and gpu then
      pcall(gpu.bind, screenAddress)
      local w, h = 50, 16
      pcall(function() w, h = gpu.getResolution() end)
      pcall(gpu.setBackground, BG)
      pcall(gpu.setForeground, 0xFF6666)
      pcall(gpu.fill, 1, 1, w, h, " ")
      pcall(gpu.set, 2, 2, "ASTRAOS BIOS - BOOT ERROR")
      pcall(gpu.setForeground, FG)
      pcall(gpu.set, 2, 4, tostring(message):sub(1, math.max(1, w - 2)))
      pcall(gpu.set, 2, 6, "Check init.lua and /system/main.lua")
    end
  else
    pcall(computer.beep, 440, 0.5)
  end
  pauseForever()
end

local function readFile(fs, path)
  local handle, reason = fs.open(path, "r")
  if not handle then return nil, reason or "could not open file" end
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

local function clip(text, maxWidth)
  text = tostring(text or "")
  if maxWidth <= 0 then return "" end
  if unicode and unicode.wtrunc then
    local ok, value = pcall(unicode.wtrunc, text, maxWidth)
    if ok and value then return value end
  end
  return text:sub(1, maxWidth)
end

local function formatBytes(value)
  value = tonumber(value)
  if not value then return "?" end
  local units, index = {"B", "KiB", "MiB", "GiB"}, 1
  while value >= 1024 and index < #units do value, index = value / 1024, index + 1 end
  if index == 1 then return string.format("%d %s", value, units[index]) end
  return string.format("%.1f %s", value, units[index])
end

local function collectFilesystems()
  local entries = {}
  for address in component.list("filesystem", true) do
    local ok, fs = pcall(component.proxy, address)
    if ok and fs then
      local labelOk, label = pcall(fs.getLabel)
      if not labelOk or not label or label == "" then label = "Filesystem " .. tostring(address):sub(1, 8) end
      local existsOk, hasKernel = pcall(fs.exists, "/system/main.lua")
      local totalOk, total = pcall(fs.spaceTotal)
      local usedOk, used = pcall(fs.spaceUsed)
      local readOnlyOk, readOnly = pcall(fs.isReadOnly)
      local lowered = string.lower(tostring(label))
      entries[#entries + 1] = {
        address = address,
        fs = fs,
        label = tostring(label),
        isRaid = lowered:find("raid", 1, true) ~= nil,
        bootable = existsOk and hasKernel == true,
        total = totalOk and total or nil,
        used = usedOk and used or nil,
        readOnly = readOnlyOk and readOnly or false
      }
    end
  end
  return entries
end

local function drawBootPrompt(gpu, width, height, defaultEntry, canSelect)
  pcall(gpu.setBackground, BG)
  pcall(gpu.setForeground, FG)
  pcall(gpu.fill, 1, 1, width, height, " ")
  local function line(y, text, color)
    if y < 1 or y > height then return end
    pcall(gpu.setBackground, BG)
    pcall(gpu.setForeground, color or FG)
    pcall(gpu.fill, 1, y, width, 1, " ")
    pcall(gpu.set, 2, y, clip(text, math.max(0, width - 2)))
  end
  line(2, "       /\\", ACCENT)
  line(3, "      /  \\    A S T R A O S", ACCENT)
  line(4, "     /____\\", ACCENT)
  line(6, "ASTRAOS BIOS", FG)
  if canSelect then
    line(8, "Press ENTER within 2 seconds", ACCENT)
    line(9, "to choose a boot device.", ACCENT)
  else
    line(8, "No keyboard detected.", MUTED)
    line(9, "Starting the default device.", MUTED)
  end
  line(11, "Default: " .. tostring(defaultEntry.label), FG)
  line(13, "RAID appears as one filesystem.", MUTED)
end

local function drawBootMenu(gpu, width, height, entries, selected, message)
  pcall(gpu.setBackground, BG)
  pcall(gpu.setForeground, FG)
  pcall(gpu.fill, 1, 1, width, height, " ")
  local function line(y, text, color, background)
    if y < 1 or y > height then return end
    pcall(gpu.setBackground, background or BG)
    pcall(gpu.setForeground, color or FG)
    pcall(gpu.fill, 1, y, width, 1, " ")
    pcall(gpu.set, 2, y, clip(text, math.max(0, width - 2)))
  end

  line(2, "       /\\", ACCENT)
  line(3, "      /  \\    A S T R A O S", ACCENT)
  line(4, "     /____\\", ACCENT)
  line(6, "BIOS BOOT MANAGER", FG)
  line(7, "Select AstraOS filesystem (disk or RAID array):", MUTED)

  local firstRow = 9
  local maxRows = math.max(1, height - firstRow - 3)
  local firstEntry = math.max(1, math.min(selected, #entries - maxRows + 1))
  local lastEntry = math.min(#entries, firstEntry + maxRows - 1)
  local labelWidth = math.max(6, math.min(18, width - 38))
  for i = firstEntry, lastEntry do
    local entry = entries[i]
    local marker = i == selected and ">" or " "
    local kind = entry.isRaid and "RAID" or "DISK"
    local status = entry.bootable and "READY" or "NO OS"
    local size = entry.total and formatBytes(entry.total) or "size ?"
    local defaultMark = entry.isDefault and " *" or ""
    local readonlyMark = entry.readOnly and " RO" or ""
    local labelFormat = "%-" .. tostring(labelWidth) .. "s"
    local text = string.format("%s %d. %-4s " .. labelFormat .. " %-7s %s%s%s",
      marker, i, kind, entry.label, size, status, defaultMark, readonlyMark)
    line(firstRow + i - firstEntry, text, i == selected and BG or FG, i == selected and ACCENT or BG)
  end
  if #entries > maxRows then
    line(firstRow + maxRows, string.format("Showing %d-%d of %d", firstEntry, lastEntry, #entries), MUTED)
  end
  if message then line(height - 2, message, 0xFFCC66) end
  line(height - 1, "UP/DOWN select | ENTER boot and save", MUTED)
  line(height, "ESC: default device | RAID is a filesystem", MUTED)
end

local function saveBootChoice(entry)
  if computer.setBootAddress then pcall(computer.setBootAddress, entry.address) end
  return entry.fs, entry.address
end

local function chooseFilesystem(entries)
  local bootAddress
  if computer.getBootAddress then
    local ok, value = pcall(computer.getBootAddress)
    if ok then bootAddress = value end
  end

  local selected
  for i, entry in ipairs(entries) do
    entry.isDefault = entry.address == bootAddress
    if entry.bootable and entry.isDefault then selected = i end
  end
  if not selected then
    for i, entry in ipairs(entries) do
      if entry.bootable then selected = i; break end
    end
  end
  if not selected then return nil end
  local defaultSelected = selected

  local gpuAddress, screenAddress = firstComponent("gpu"), firstComponent("screen")
  local keyboardAddress = firstComponent("keyboard")
  local gpu
  if gpuAddress and screenAddress then
    local ok, proxy = pcall(component.proxy, gpuAddress)
    if ok then gpu = proxy end
  end
  if not gpu then return entries[selected].fs, entries[selected].address end

  pcall(gpu.bind, screenAddress)
  local width, height = 80, 25
  pcall(function() width, height = gpu.getResolution() end)
  drawBootPrompt(gpu, width, height, entries[selected], keyboardAddress ~= nil)
  if not keyboardAddress then return entries[selected].fs, entries[selected].address end

  local openMenu = false
  local clockOk, startTime = false, 0
  if computer.uptime then clockOk, startTime = pcall(computer.uptime) end
  local pollCount = 0
  while true do
    local remaining = 0.1
    if clockOk then
      local nowOk, now = pcall(computer.uptime)
      if not nowOk or now - startTime >= 2 then break end
      remaining = math.min(0.1, 2 - (now - startTime))
    elseif pollCount >= 20 then
      break
    end
    local ok, signal, _, char, code = pcall(computer.pullSignal, remaining)
    if not ok then break end
    if signal == "key_down" and (code == 28 or char == 13) then
      openMenu = true
      break
    end
    pollCount = pollCount + 1
  end
  if not openMenu then return entries[defaultSelected].fs, entries[defaultSelected].address end

  drawBootMenu(gpu, width, height, entries, selected)
  local message
  while true do
    local ok, signal, _, char, code = pcall(computer.pullSignal)
    if not ok then return entries[defaultSelected].fs, entries[defaultSelected].address end
    if signal == "key_down" then
      if code == 200 then
        selected = selected - 1
        if selected < 1 then selected = #entries end
        message = nil
      elseif code == 208 then
        selected = selected + 1
        if selected > #entries then selected = 1 end
        message = nil
      elseif code == 28 or char == 13 then
        if entries[selected].bootable then return saveBootChoice(entries[selected]) end
        message = "This filesystem has no /system/main.lua"
      elseif code == 1 then
        return entries[defaultSelected].fs, entries[defaultSelected].address
      elseif type(char) == "number" and char >= 49 and char <= 57 then
        local target = char - 48
        if entries[target] then selected = target; message = nil end
      end
      drawBootMenu(gpu, width, height, entries, selected, message)
    end
  end
end

local filesystems = collectFilesystems()
local bootFs, bootFsAddress = chooseFilesystem(filesystems)
if not bootFs then
  showFailure("no AstraOS installation found on connected filesystems")
end

local source, reason = readFile(bootFs, "/system/main.lua")
if not source then showFailure("/system/main.lua: " .. tostring(reason)) end
local chunk, syntaxError = load(source, "@/system/main.lua", "t", _G)
if not chunk then showFailure(syntaxError) end
local ok, runError = pcall(chunk, bootFs, bootFsAddress)
if not ok then showFailure(runError) end
-- A custom OS must keep running; returning here means the kernel exited.
pauseForever()
