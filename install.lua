-- AstraOS installer. Run from OpenOS:
-- lua /path/to/astraos/install.lua <filesystem-component-address>
local okFs, filesystem = pcall(require, "filesystem")
local okComponent, component = pcall(require, "component")
if not okFs or not okComponent then
  io.stderr:write("Установщик нужно запускать из OpenOS.\n")
  return
end

local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local sourceRoot = filesystem.path(source)
if sourceRoot == "" then sourceRoot = "/" end
local targetAddress = ...
if not targetAddress or targetAddress == "" then
  io.stderr:write("Укажи адрес filesystem-компонента.\n")
  io.stderr:write("Пример: lua " .. source .. " <адрес-диска>\n\n")
  io.stderr:write("Адреса дисков:\n")
  for address in component.list("filesystem", true) do io.stderr:write("  " .. address .. "\n") end
  return
end

local fullAddress, addressError = component.get(targetAddress, "filesystem")
if not fullAddress then
  io.stderr:write("Не найден filesystem: " .. tostring(addressError) .. "\n")
  return
end
local target = component.proxy(fullAddress)
if target.isReadOnly() then
  io.stderr:write("Целевой диск доступен только для чтения.\n")
  return
end

local function readSource(path)
  local file, reason = filesystem.open(path, "r")
  if not file then return nil, reason end
  local chunks = {}
  while true do
    local data, err = file:read(4096)
    if not data then
      file:close()
      if err then return nil, err end
      break
    end
    chunks[#chunks + 1] = data
  end
  return table.concat(chunks)
end

local function writeTarget(path, data)
  local handle, reason = target.open(path, "w")
  if not handle then return nil, reason end
  local wrote, writeError = target.write(handle, data)
  target.close(handle)
  if not wrote then return nil, writeError end
  return true
end

local bootSource, reason = readSource(filesystem.concat(sourceRoot, "init.lua"))
if not bootSource then io.stderr:write("Не прочитать init.lua: " .. tostring(reason) .. "\n"); return end
local kernelSource
kernelSource, reason = readSource(filesystem.concat(sourceRoot, "system/main.lua"))
if not kernelSource then io.stderr:write("Не прочитать system/main.lua: " .. tostring(reason) .. "\n"); return end

if target.exists("/init.lua.astraos-backup") then
  io.stderr:write("На диске уже есть /init.lua.astraos-backup; отмена, чтобы не затереть резервную копию.\n")
  return
end
if target.exists("/init.lua") then
  local backedUp, backupError = target.rename("/init.lua", "/init.lua.astraos-backup")
  if not backedUp then io.stderr:write("Не удалось сохранить старый init.lua: " .. tostring(backupError) .. "\n"); return end
end

local dirOk, dirError = target.makeDirectory("/system")
if not dirOk and not target.isDirectory("/system") then
  io.stderr:write("Не удалось создать /system: " .. tostring(dirError) .. "\n")
  if target.exists("/init.lua.astraos-backup") then target.rename("/init.lua.astraos-backup", "/init.lua") end
  return
end

local kernelOk, kernelError = writeTarget("/system/main.lua", kernelSource)
if not kernelOk then
  io.stderr:write("Ошибка записи ядра: " .. tostring(kernelError) .. "\n")
  if target.exists("/init.lua.astraos-backup") then target.rename("/init.lua.astraos-backup", "/init.lua") end
  return
end
local bootOk, bootError = writeTarget("/init.lua", bootSource)
if not bootOk then
  io.stderr:write("Ошибка записи загрузчика: " .. tostring(bootError) .. "\n")
  if target.exists("/init.lua.astraos-backup") then target.rename("/init.lua.astraos-backup", "/init.lua") end
  return
end

io.stdout:write("AstraOS установлена на filesystem " .. fullAddress .. ".\n")
io.stdout:write("Старый загрузчик сохранён как /init.lua.astraos-backup (если он был).\n")
io.stdout:write("В EEPROM/BIOS выбери этот диск как boot filesystem и перезагрузи компьютер.\n")
