-- AstraOS online installer for OpenOS.
-- It is fetched from GitHub with wget, then run from OpenOS:
-- lua /tmp/astraos-install.lua
local REPO = "https://raw.githubusercontent.com/FoxFord1A/AstraOS-OpenComputers/main"

local function stop(message)
  io.stderr:write("AstraOS installer: " .. tostring(message) .. "\n")
  return false
end

local okComponent, component = pcall(require, "component")
local okComputer, computer = pcall(require, "computer")
local okInternet, internet = pcall(require, "internet")
if not okComponent or not okComputer or not okInternet then
  stop("запусти этот установщик из OpenOS; нужен работающий OpenOS")
  return
end
if not component.isAvailable("internet") then
  stop("нужна интернет-карта OpenComputers и разрешённый HTTP(S) в настройках мода")
  return
end

local function download(path)
  local url = REPO .. path
  local ok, response = pcall(internet.request, url)
  if not ok or not response then return nil, response or "HTTP request failed" end
  local chunks = {}
  local readOk, readError = pcall(function()
    for chunk in response do chunks[#chunks + 1] = chunk end
  end)
  if not readOk then return nil, readError end
  return table.concat(chunks)
end

io.write("Скачиваю AstraOS с GitHub...\n")
local initSource, reason = download("/init.lua")
if not initSource then stop("не удалось скачать init.lua: " .. tostring(reason)); return end
local kernelSource
kernelSource, reason = download("/system/main.lua")
if not kernelSource then stop("не удалось скачать ядро: " .. tostring(reason)); return end

local initChunk, initError = load(initSource, "@/init.lua", "t", {})
if not initChunk then stop("проверка init.lua не прошла: " .. tostring(initError)); return end
local kernelChunk, kernelError = load(kernelSource, "@/system/main.lua", "t", {})
if not kernelChunk then stop("проверка ядра не прошла: " .. tostring(kernelError)); return end

local filesystems = {}
local temporaryAddress = computer.tmpAddress and computer.tmpAddress()
for address in component.list("filesystem", true) do
  local ok, fs = pcall(component.proxy, address)
  if ok and fs then
    local roOk, readOnly = pcall(fs.isReadOnly)
    if roOk and not readOnly and address ~= temporaryAddress then
      local labelOk, label = pcall(fs.getLabel)
      filesystems[#filesystems + 1] = {
        address = address,
        label = labelOk and (label or "без метки") or "без метки",
        fs = fs
      }
    end
  end
end
if #filesystems == 0 then stop("не найден постоянный доступный для записи filesystem"); return end

table.sort(filesystems, function(a, b) return a.address < b.address end)
io.write("\nВыбери загрузочный диск из доступных файловых систем:\n")
for i, item in ipairs(filesystems) do
  io.write(string.format("  %d) %s  [%s]\n", i, item.label, item.address))
end
io.write("Номер диска: ")
local choice = tonumber(io.read("*l"))
if not choice or choice < 1 or choice > #filesystems or choice % 1 ~= 0 then
  stop("неверный номер"); return
end
local target = filesystems[choice]
local fs = target.fs

local initBackup = "/init.lua.astraos-backup"
local kernelBackup = "/system/main.lua.astraos-backup"
if fs.exists(initBackup) or fs.exists(kernelBackup) then
  stop("на выбранном диске уже есть резервная копия AstraOS; переименуй или удали её вручную, чтобы не потерять")
  return
end
if fs.exists("/system") and not fs.isDirectory("/system") then
  stop("путь /system уже занят файлом")
  return
end
if fs.exists("/system/main.lua") and fs.isDirectory("/system/main.lua") then
  stop("путь /system/main.lua уже занят каталогом")
  return
end

io.write("\nБудут заменены загрузочные файлы на диске " .. target.label .. " [" .. target.address .. "].\n")
io.write("Существующие init.lua и /system/main.lua сохранятся в резервных копиях.\n")
io.write("Для продолжения введи INSTALL: ")
if io.read("*l") ~= "INSTALL" then io.write("Отменено.\n"); return end
if not fs.makeDirectory("/system") and not fs.isDirectory("/system") then
  stop("не удалось создать /system")
  return
end

local hadInit = fs.exists("/init.lua")
local hadKernel = fs.exists("/system/main.lua")
if hadInit then
  local moved, moveError = fs.rename("/init.lua", initBackup)
  if not moved then stop("не удалось сохранить прежний init.lua: " .. tostring(moveError)); return end
end
if hadKernel then
  local moved, moveError = fs.rename("/system/main.lua", kernelBackup)
  if not moved then
    if hadInit then fs.rename(initBackup, "/init.lua") end
    stop("не удалось сохранить прежнее ядро: " .. tostring(moveError)); return
  end
end

local function writeFile(path, data)
  local handle, openError = fs.open(path, "w")
  if not handle then return nil, openError end
  local wrote, writeError = fs.write(handle, data)
  fs.close(handle)
  if not wrote then pcall(fs.remove, path); return nil, writeError end
  return true
end

local kernelOk, kernelWriteError = writeFile("/system/main.lua", kernelSource)
local initOk, initWriteError
if kernelOk then initOk, initWriteError = writeFile("/init.lua", initSource) end
if not kernelOk or not initOk then
  pcall(fs.remove, "/init.lua")
  pcall(fs.remove, "/system/main.lua")
  if hadKernel then pcall(fs.rename, kernelBackup, "/system/main.lua") end
  if hadInit then pcall(fs.rename, initBackup, "/init.lua") end
  stop("не удалось записать загрузочные файлы: " .. tostring(kernelWriteError or initWriteError))
  return
end

io.write("\nAstraOS установлена на " .. target.label .. " [" .. target.address .. "].\n")
io.write("Перезагрузи компьютер и выбери этот диск в EEPROM/BIOS как boot filesystem.\n")
if hadInit or hadKernel then
  io.write("Резервные копии старых файлов оставлены на выбранном диске.\n")
end
