-- AstraOS 0.2 - small standalone shell OS for OpenComputers.
-- Arguments are the boot filesystem proxy and its component address.
local fs, bootAddress = ...
local gpu, screen
local function firstComponent(kind)
  local iter = component.list(kind, true)
  local address = iter and iter()
  if not address then return nil end
  local ok, proxy = pcall(component.proxy, address)
  if ok then return proxy, address end
end

gpu = firstComponent("gpu")
local _, screenAddress = firstComponent("screen")
if not gpu or not screenAddress then
  pcall(computer.beep, 300, 0.3)
  error("AstraOS требует GPU и экран OpenComputers")
end
pcall(gpu.bind, screenAddress)

local BG, FG, ACCENT, MUTED = 0x101820, 0xE6EDF3, 0x55D6BE, 0x8B98A5
pcall(gpu.setBackground, BG)
pcall(gpu.setForeground, FG)
local width, height = 50, 16
pcall(function() width, height = gpu.getResolution() end)
local row = 1
local cwd = "/"
local history, historyIndex = {}, 0
local unpackValues = table.unpack or unpack

local function textWidth(s)
  if unicode and unicode.wlen then
    local ok, value = pcall(unicode.wlen, s)
    if ok and value then return value end
  end
  return #s
end

local function clip(s, maxWidth)
  if maxWidth <= 0 then return "" end
  if textWidth(s) <= maxWidth then return s end
  if unicode and unicode.sub then
    local ok, value = pcall(unicode.sub, s, 1, maxWidth)
    if ok then return value end
  end
  return s:sub(1, maxWidth)
end

local function scrollIfNeeded()
  if row <= height then return end
  pcall(gpu.copy, 1, 2, width, math.max(1, height - 1), 0, -1)
  pcall(gpu.setBackground, BG)
  pcall(gpu.fill, 1, height, width, 1, " ")
  row = height
end

local function newline()
  row = row + 1
  scrollIfNeeded()
end

local function putLine(value, color)
  local s = tostring(value or "")
  if color then pcall(gpu.setForeground, color) else pcall(gpu.setForeground, FG) end
  local pieces = {}
  for part in (s .. "\n"):gmatch("(.-)\n") do pieces[#pieces + 1] = part end
  for _, part in ipairs(pieces) do
    scrollIfNeeded()
    pcall(gpu.setBackground, BG)
    pcall(gpu.fill, 1, row, width, 1, " ")
    pcall(gpu.set, 1, row, clip(part, width))
    newline()
  end
  pcall(gpu.setForeground, FG)
end

local function clearScreen()
  pcall(gpu.setBackground, BG)
  pcall(gpu.setForeground, FG)
  pcall(gpu.fill, 1, 1, width, height, " ")
  row = 1
end

local function normalize(path)
  path = tostring(path or "")
  if path == "" then path = cwd end
  if path:sub(1, 1) ~= "/" then path = cwd .. "/" .. path end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end

local function basename(path)
  local clean = normalize(path)
  if clean == "/" then return "/" end
  return clean:match("([^/]+)$") or clean
end

local function readFile(path)
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

local function writeFile(path, data)
  local handle, reason = fs.open(path, "w")
  if not handle then return nil, reason or "не удалось создать файл" end
  local ok, err = fs.write(handle, data)
  pcall(fs.close, handle)
  if not ok then return nil, err or "ошибка записи" end
  return true
end

local function parse(line)
  local result, token = {}, ""
  local quote, escaped, active = nil, false, false
  for i = 1, #line do
    local ch = line:sub(i, i)
    if escaped then
      token, escaped = token .. ch, false
      active = true
    elseif ch == "\\" then
      escaped, active = true, true
    elseif quote then
      if ch == quote then quote = nil else token = token .. ch end
      active = true
    elseif ch == "'" or ch == '"' then
      quote, active = ch, true
    elseif ch:match("%s") then
      if active then result[#result + 1], token, active = token, "", false end
    else
      token, active = token .. ch, true
    end
  end
  if escaped then token = token .. "\\" end
  if active then result[#result + 1] = token end
  return result
end

local function readLine(prompt)
  prompt = tostring(prompt or "")
  if textWidth(prompt) > width - 1 then prompt = clip(prompt, width - 1) end
  scrollIfNeeded()
  local promptX = textWidth(prompt) + 1
  pcall(gpu.setForeground, ACCENT)
  pcall(gpu.setBackground, BG)
  pcall(gpu.fill, 1, row, width, 1, " ")
  pcall(gpu.set, 1, row, prompt)
  pcall(gpu.setForeground, FG)
  local line = ""
  local function redraw()
    local available = math.max(0, width - promptX + 1)
    pcall(gpu.setBackground, BG)
    pcall(gpu.fill, promptX, row, available, 1, " ")
    local show = line
    if textWidth(show) > available then
      if unicode and unicode.sub then
        local ok, tail = pcall(unicode.sub, show, textWidth(show) - available + 1, textWidth(show))
        if ok then show = tail else show = show:sub(-available) end
      else
        show = show:sub(-available)
      end
    end
    pcall(gpu.set, promptX, row, show)
  end
  redraw()
  while true do
    local signal, _, char, code = computer.pullSignal(0.15)
    if signal == "key_down" then
      if code == 28 or char == 13 then
        newline()
        return line
      elseif code == 14 or char == 8 then
        if #line > 0 then
          if unicode and unicode.sub and unicode.len then
            local ok, length = pcall(unicode.len, line)
            if ok and length then
              local cutOk, value = pcall(unicode.sub, line, 1, length - 1)
              line = cutOk and value or line:sub(1, -2)
            else line = line:sub(1, -2) end
          else
            line = line:sub(1, -2)
          end
          redraw()
        end
      elseif code == 200 then
        if #history > 0 then
          historyIndex = math.max(1, historyIndex - 1)
          line = history[historyIndex]
          redraw()
        end
      elseif code == 208 then
        if #history > 0 and historyIndex < #history then
          historyIndex = historyIndex + 1
          line = history[historyIndex]
        else
          historyIndex = #history + 1
          line = ""
        end
        redraw()
      elseif char == 3 then
        newline()
        return ""
      elseif type(char) == "number" and char > 0 and unicode and unicode.char then
        local ok, value = pcall(unicode.char, char)
        if ok and value and #line < 240 then line = line .. value; redraw() end
      end
    end
  end
end

local function listDirectory(path)
  local ok, entries = pcall(fs.list, path)
  if not ok or type(entries) ~= "table" then return nil, "не удалось прочитать каталог" end
  table.sort(entries)
  return entries
end

local function formatBytes(value)
  value = tonumber(value) or 0
  local units = {"B", "KiB", "MiB", "GiB"}
  local index = 1
  while value >= 1024 and index < #units do value, index = value / 1024, index + 1 end
  if index == 1 then return string.format("%d %s", value, units[index]) end
  return string.format("%.1f %s", value, units[index])
end

local function splitLines(data)
  local lines = {}
  if data == "" then return lines end
  for line in (data .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if data:sub(-1) == "\n" then table.remove(lines) end
  return lines
end

local function directorySize(path)
  local ok, isDir = pcall(fs.isDirectory, path)
  if not ok or not isDir then
    local sizeOk, size = pcall(fs.size, path)
    return sizeOk and tonumber(size) or 0
  end
  local entries = listDirectory(path)
  if not entries then return 0 end
  local total = 0
  for _, entry in ipairs(entries) do total = total + directorySize(normalize(path .. "/" .. entry)) end
  return total
end

local function cmdHelp()
  putLine("AstraOS — команды:", ACCENT)
  putLine("Файлы: ls cd pwd cat head tail grep wc find tree mkdir rmdir touch rm cp mv du df", MUTED)
  putLine("Система: help man about version sysinfo free uptime hostname date components resolution", MUTED)
  putLine("Shell: echo clear history alias unalias which lua edit sleep wget reboot shutdown", MUTED)
  putLine("Пути абсолютные (/home/file) или относительно текущего каталога.")
  putLine("Это основной совместимый набор; см. man <команда>.", MUTED)
end

local commands = {}
local aliases = {}
commands.help = cmdHelp
commands.clear = function() clearScreen() end
commands.cls = commands.clear
commands.about = function()
  putLine("AstraOS 0.2 — компактная ОС для OpenComputers", ACCENT)
  putLine("Lua BIOS напрямую; без библиотек OpenOS. Загружена с " .. tostring(bootAddress or "авто-носителя"))
end
commands.version = commands.about
commands.pwd = function() putLine(cwd) end
commands.ls = function(args)
  local showLong, i = false, 1
  while args[i] and args[i]:sub(1, 1) == "-" and args[i] ~= "-" do
    if args[i] == "--" then i = i + 1; break end
    for flag in args[i]:sub(2):gmatch(".") do
      if flag == "l" or flag == "a" then showLong = showLong or flag == "l"
      else putLine("ls: неизвестная опция -" .. flag, 0xFF6666); return end
    end
    i = i + 1
  end
  local path = normalize(args[i] or ".")
  local entries, reason = listDirectory(path)
  if not entries then putLine("ls: " .. tostring(reason), 0xFF6666); return end
  if #entries == 0 then putLine("(пусто)", MUTED); return end
  for _, entry in ipairs(entries) do
    if showLong then
      local child = normalize(path .. "/" .. entry)
      local ok, isDir = pcall(fs.isDirectory, child)
      local sizeOk, size = pcall(fs.size, child)
      putLine(string.format("%s %8s %s", ok and isDir and "d" or "-", sizeOk and formatBytes(size) or "?", entry))
    else
      putLine(entry)
    end
  end
end
commands.cd = function(args)
  local path = normalize(args[1] or "/")
  local ok, isDir = pcall(fs.isDirectory, path)
  if ok and isDir then cwd = path else putLine("cd: каталог не найден: " .. path, 0xFF6666) end
end
commands.cat = function(args)
  if not args[1] then putLine("Использование: cat <файл>", 0xFFCC66); return end
  local path = normalize(args[1])
  local data, reason = readFile(path)
  if not data then putLine("cat: " .. tostring(reason), 0xFF6666); return end
  if data == "" then putLine(""); return end
  for line in (data .. "\n"):gmatch("(.-)\n") do putLine(line) end
end
commands.echo = function(args) putLine(table.concat(args, " ")) end
commands.mkdir = function(args)
  local i = args[1] == "-p" and 2 or 1
  if not args[i] then putLine("Использование: mkdir [-p] <каталог>", 0xFFCC66); return end
  local ok, result = pcall(fs.makeDirectory, normalize(args[i]))
  if not ok or not result then putLine("mkdir: ошибка создания", 0xFF6666) end
end
commands.touch = function(args)
  if not args[1] then putLine("Использование: touch <файл>", 0xFFCC66); return end
  local path = normalize(args[1])
  local handle, reason = fs.open(path, "a")
  if not handle then putLine("touch: " .. tostring(reason), 0xFF6666); return end
  pcall(fs.close, handle)
end
commands.rm = function(args)
  local recursive, force, i = false, false, 1
  while args[i] and args[i]:sub(1, 1) == "-" and args[i] ~= "-" do
    if args[i] == "--recursive" then recursive = true
    elseif args[i] == "--force" then force = true
    elseif args[i] == "--" then i = i + 1; break
    else
      for flag in args[i]:sub(2):gmatch(".") do
        if flag == "r" or flag == "R" then recursive = true
        elseif flag == "f" then force = true
        else putLine("rm: неизвестная опция -" .. flag, 0xFF6666); return end
      end
    end
    i = i + 1
  end
  if not args[i] then putLine("Использование: rm [-r] [-f] <путь>", 0xFFCC66); return end
  local function removePath(path)
    if path == "/" or path == "/init.lua" or path == "/system" or path:sub(1, 8) == "/system/" then
      return nil, "защищён системный путь " .. path
    end
    local existsOk, exists = pcall(fs.exists, path)
    if existsOk and not exists then return force and true or nil, "путь не найден: " .. path end
    local dirOk, isDir = pcall(fs.isDirectory, path)
    if dirOk and isDir then
      if not recursive then return nil, "это каталог; используй rm -r" end
      local entries, reason = listDirectory(path)
      if not entries then return nil, reason end
      for _, entry in ipairs(entries) do
        local removed, removeError = removePath(normalize(path .. "/" .. entry))
        if not removed then return nil, removeError end
      end
    end
    local ok, result = pcall(fs.remove, path)
    if not ok or not result then return nil, "не удалось удалить " .. path end
    return true
  end
  local path = normalize(args[i])
  local ok, reason = removePath(path)
  if not ok then putLine("rm: " .. tostring(reason), 0xFF6666) end
end
local function copyPath(source, destination, recursive)
  local sourceOk, sourceIsDir = pcall(fs.isDirectory, source)
  if sourceOk and sourceIsDir then
    if not recursive then return nil, "это каталог; используй cp -r" end
    local destinationOk, destinationIsDir = pcall(fs.isDirectory, destination)
    if destinationOk and destinationIsDir then destination = normalize(destination .. "/" .. basename(source)) end
    local sourcePrefix = source == "/" and "/" or (source .. "/")
    if source == "/" or destination == source or destination:sub(1, #sourcePrefix) == sourcePrefix then
      return nil, "нельзя копировать каталог внутрь самого себя"
    end
    local made, makeError = fs.makeDirectory(destination)
    if not made and not fs.isDirectory(destination) then return nil, makeError or "не удалось создать каталог" end
    local entries, reason = listDirectory(source)
    if not entries then return nil, reason end
    for _, entry in ipairs(entries) do
      local ok, err = copyPath(normalize(source .. "/" .. entry), normalize(destination .. "/" .. entry), true)
      if not ok then return nil, err end
    end
    return true
  end
  local src, reason = readFile(source)
  if not src then return nil, reason end
  local destinationOk, destinationIsDir = pcall(fs.isDirectory, destination)
  if destinationOk and destinationIsDir then destination = normalize(destination .. "/" .. basename(source)) end
  return writeFile(destination, src)
end
commands.cp = function(args)
  local recursive, i = false, 1
  if args[1] == "-r" or args[1] == "-R" or args[1] == "-a" then recursive, i = true, 2 end
  if not args[i] or not args[i + 1] then putLine("Использование: cp [-r] <источник> <назначение>", 0xFFCC66); return end
  local ok, reason = copyPath(normalize(args[i]), normalize(args[i + 1]), recursive)
  if not ok then putLine("cp: " .. tostring(reason), 0xFF6666) end
end
commands.mv = function(args)
  if not args[1] or not args[2] then putLine("Использование: mv <источник> <назначение>", 0xFFCC66); return end
  local from, to = normalize(args[1]), normalize(args[2])
  local isDirOk, isDir = pcall(fs.isDirectory, to)
  if isDirOk and isDir then to = normalize(to .. "/" .. basename(from)) end
  local ok, result = pcall(fs.rename, from, to)
  if not ok or not result then putLine("mv: не удалось переместить файл", 0xFF6666) end
end
commands.edit = function(args)
  if not args[1] then putLine("Использование: edit <файл>", 0xFFCC66); return end
  local path = normalize(args[1])
  putLine("Простой редактор: вводи текст построчно.", ACCENT)
  putLine(".save — сохранить; .cancel — отменить. Существующий файл будет заменён.", MUTED)
  local lines = {}
  while true do
    local input = readLine("edit> ")
    if input == ".save" then break end
    if input == ".cancel" then putLine("Изменения отменены.", MUTED); return end
    lines[#lines + 1] = input
  end
  local ok, reason = writeFile(path, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
  if ok then putLine("Сохранено: " .. path, ACCENT) else putLine("edit: " .. tostring(reason), 0xFF6666) end
end
local function runLua(path, args)
  local source, reason = readFile(path)
  if not source then putLine("lua: " .. tostring(reason), 0xFF6666); return end
  local chunk, syntaxError = load(source, "@" .. path, "t", _G)
  if not chunk then putLine("Синтаксическая ошибка: " .. tostring(syntaxError), 0xFF6666); return end
  local previousArg = _G.arg
  _G.arg = args
  local ok, a, b, c = pcall(chunk, unpackValues(args))
  _G.arg = previousArg
  if not ok then putLine("Ошибка скрипта: " .. tostring(a), 0xFF6666)
  elseif a ~= nil then
    putLine(tostring(a))
    if b ~= nil then putLine(tostring(b)) end
    if c ~= nil then putLine(tostring(c)) end
  end
end
commands.lua = function(args)
  if not args[1] then putLine("Использование: lua <файл.lua> [аргументы]", 0xFFCC66); return end
  local params = {}
  for i = 2, #args do params[#params + 1] = args[i] end
  runLua(normalize(args[1]), params)
end
commands.sysinfo = function()
  local function safe(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or "?"
  end
  putLine("AstraOS 0.2 | Lua " .. tostring(_VERSION), ACCENT)
  putLine("CPU: " .. safe(computer.address))
  putLine("RAM: " .. safe(computer.freeMemory) .. " / " .. safe(computer.totalMemory) .. " байт")
  putLine("Энергия: " .. safe(computer.energy) .. " / " .. safe(computer.maxEnergy))
  putLine("Время работы: " .. safe(computer.uptime) .. " с")
  putLine("Загрузочный FS: " .. tostring(bootAddress or "не указан"))
end
commands.components = function()
  for address, kind in component.list() do putLine(kind .. "  " .. address) end
end
commands.address = function() putLine(computer.address()) end
commands.hostname = function()
  local address = tostring(computer.address and computer.address() or "astraos")
  putLine("astraos-" .. address:sub(1, 8))
end
commands.free = function()
  putLine("RAM свободно: " .. formatBytes(computer.freeMemory()) .. " / " .. formatBytes(computer.totalMemory()))
  putLine("Энергия: " .. tostring(math.floor(computer.energy())) .. " / " .. tostring(math.floor(computer.maxEnergy())))
end
commands.uptime = function()
  local seconds = math.floor(computer.uptime())
  local days = math.floor(seconds / 86400); seconds = seconds % 86400
  local hours = math.floor(seconds / 3600); seconds = seconds % 3600
  local minutes = math.floor(seconds / 60); seconds = seconds % 60
  putLine(string.format("%dд %02d:%02d:%02d", days, hours, minutes, seconds))
end
commands.df = function()
  putLine("FILESYSTEM       USED          FREE          TOTAL", ACCENT)
  for address, kind in component.list("filesystem", true) do
    local ok, proxy = pcall(component.proxy, address)
    if ok and proxy then
      local labelOk, label = pcall(proxy.getLabel)
      local usedOk, used = pcall(proxy.spaceUsed)
      local totalOk, total = pcall(proxy.spaceTotal)
      if usedOk and totalOk then
        local name = labelOk and label and label ~= "" and label or address:sub(1, 8)
        putLine(string.format("%-15s %-12s %-12s %s", tostring(name), formatBytes(used), formatBytes(total - used), formatBytes(total)))
      else
        putLine(tostring(kind) .. " " .. address .. " (нет данных о размере)", MUTED)
      end
    end
  end
end
commands.du = function(args)
  local path = normalize(args[1] or ".")
  local existsOk, exists = pcall(fs.exists, path)
  if not existsOk or not exists then putLine("du: путь не найден: " .. path, 0xFF6666); return end
  putLine(formatBytes(directorySize(path)) .. "  " .. path)
end
local function printFileLines(args, fromEnd)
  local index, count = 1, 10
  if args[index] == "-n" then
    count = tonumber(args[index + 1]) or 10
    index = index + 2
  end
  if not args[index] then putLine("Использование: " .. (fromEnd and "tail" or "head") .. " [-n число] <файл>", 0xFFCC66); return end
  count = math.max(0, math.min(1000, math.floor(count)))
  local path = normalize(args[index])
  local data, reason = readFile(path)
  if not data then putLine((fromEnd and "tail: " or "head: ") .. tostring(reason), 0xFF6666); return end
  local lines = splitLines(data)
  local first = fromEnd and math.max(1, #lines - count + 1) or 1
  local last = fromEnd and #lines or math.min(#lines, count)
  for i = first, last do putLine(lines[i]) end
end
commands.head = function(args) printFileLines(args, false) end
commands.tail = function(args) printFileLines(args, true) end
commands.wc = function(args)
  if not args[1] then putLine("Использование: wc <файл>", 0xFFCC66); return end
  local path = normalize(args[1])
  local data, reason = readFile(path)
  if not data then putLine("wc: " .. tostring(reason), 0xFF6666); return end
  local lines = 0
  for _ in data:gmatch("\n") do lines = lines + 1 end
  if #data > 0 and data:sub(-1) ~= "\n" then lines = lines + 1 end
  local words = 0
  for _ in data:gmatch("%S+") do words = words + 1 end
  putLine(string.format("%d %d %d %s", lines, words, #data, path))
end
commands.grep = function(args)
  local ignoreCase, invert, showNumber = false, false, false
  local i = 1
  while args[i] and args[i]:sub(1, 1) == "-" and args[i] ~= "-" do
    if args[i] == "--" then i = i + 1; break end
    for flag in args[i]:sub(2):gmatch(".") do
      if flag == "i" then ignoreCase = true
      elseif flag == "v" then invert = true
      elseif flag == "n" then showNumber = true
      else putLine("grep: неизвестная опция -" .. flag, 0xFF6666); return end
    end
    i = i + 1
  end
  local needle, file = args[i], args[i + 1]
  if not needle or not file then putLine("Использование: grep [-i] [-v] [-n] <текст> <файл>", 0xFFCC66); return end
  local path = normalize(file)
  local data, reason = readFile(path)
  if not data then putLine("grep: " .. tostring(reason), 0xFF6666); return end
  local lines, matches = splitLines(data), 0
  for n, line in ipairs(lines) do
    local haystack, findText = line, needle
    if ignoreCase then haystack, findText = line:lower(), needle:lower() end
    local found = haystack:find(findText, 1, true) ~= nil
    if found ~= invert then
      matches = matches + 1
      putLine((showNumber and (tostring(n) .. ":") or "") .. line)
    end
  end
  if matches == 0 then putLine("Совпадений нет.", MUTED) end
end
commands.find = function(args)
  local path, needle
  if #args == 0 then putLine("Использование: find <каталог> [имя-фрагмент]", 0xFFCC66); return end
  if #args == 1 then path, needle = cwd, args[1] else path, needle = normalize(args[1]), args[2] end
  local function walk(directory, depth)
    if depth > 32 then return end
    local entries = listDirectory(directory)
    if not entries then return end
    for _, entry in ipairs(entries) do
      local child = normalize(directory .. "/" .. entry)
      if not needle or entry:find(needle, 1, true) or child:find(needle, 1, true) then putLine(child) end
      local ok, isDir = pcall(fs.isDirectory, child)
      if ok and isDir then walk(child, depth + 1) end
    end
  end
  walk(path, 0)
end
commands.tree = function(args)
  local root = normalize(args[1] or ".")
  local maxDepth = math.max(0, math.min(8, tonumber(args[2]) or 4))
  putLine(root, ACCENT)
  local function walk(directory, prefix, depth)
    if depth >= maxDepth then return end
    local entries = listDirectory(directory)
    if not entries then return end
    for i, entry in ipairs(entries) do
      local last = i == #entries
      local child = normalize(directory .. "/" .. entry)
      local ok, isDir = pcall(fs.isDirectory, child)
      putLine(prefix .. (last and "`- " or "|- ") .. entry .. (ok and isDir and "/" or ""))
      if ok and isDir then walk(child, prefix .. (last and "   " or "|  "), depth + 1) end
    end
  end
  walk(root, "", 0)
end
commands.rmdir = function(args)
  if not args[1] then putLine("Использование: rmdir <пустой-каталог>", 0xFFCC66); return end
  local path = normalize(args[1])
  if path == "/" or path == "/system" then putLine("rmdir: защищённый каталог", 0xFF6666); return end
  local ok, isDir = pcall(fs.isDirectory, path)
  if not ok or not isDir then putLine("rmdir: это не каталог", 0xFF6666); return end
  local entries = listDirectory(path)
  if not entries then putLine("rmdir: не удалось прочитать каталог", 0xFF6666); return end
  if #entries > 0 then putLine("rmdir: каталог не пуст", 0xFF6666); return end
  local removeOk, result = pcall(fs.remove, path)
  if not removeOk or not result then putLine("rmdir: не удалось удалить каталог", 0xFF6666) end
end
commands.which = function(args)
  if not args[1] then putLine("Использование: which <команда>", 0xFFCC66); return end
  local name = args[1]
  if commands[name] then putLine(name .. ": встроенная команда"); return end
  if aliases[name] then putLine(name .. ": alias"); return end
  local path = normalize("/bin/" .. name .. ".lua")
  local ok, exists = pcall(fs.exists, path)
  if ok and exists then putLine(path) else putLine(name .. ": команда не найдена", 0xFF6666) end
end
commands.alias = function(args)
  if #args == 0 then
    local names = {}
    for name in pairs(aliases) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do putLine(name .. "=" .. table.concat(aliases[name], " ")) end
    return
  end
  if not args[2] then
    local value = aliases[args[1]]
    putLine(value and (args[1] .. "=" .. table.concat(value, " ")) or ("alias: " .. args[1] .. " не задан"), value and FG or MUTED)
    return
  end
  local value = {}
  for i = 2, #args do value[#value + 1] = args[i] end
  aliases[args[1]] = value
end
commands.unalias = function(args)
  if not args[1] then putLine("Использование: unalias <имя>", 0xFFCC66); return end
  aliases[args[1]] = nil
end
commands.history = function()
  for i, line in ipairs(history) do putLine(string.format("%3d  %s", i, line)) end
end
commands.man = function(args)
  if not args[1] then putLine("Использование: man <команда>", 0xFFCC66); return end
  local pages = {
    ls = "ls [каталог] — список файлов", cp = "cp <источник> <назначение> — копирование файла",
    mv = "mv <источник> <назначение> — перемещение/переименование", rm = "rm <путь> — удаление (системные файлы защищены)",
    grep = "grep [-inv] <текст> <файл> — поиск строк по буквальному фрагменту",
    head = "head [-n число] <файл> — первые строки", tail = "tail [-n число] <файл> — последние строки",
    wc = "wc <файл> — строки, слова и байты", find = "find <каталог> [имя-фрагмент] — поиск в дереве",
    tree = "tree [каталог] [глубина] — дерево каталогов", df = "df — занятое и свободное место файловых систем",
    du = "du [путь] — размер файла/каталога", free = "free — память и энергия", uptime = "uptime — время работы компьютера",
    alias = "alias [имя [команда ...]] — показать или задать псевдоним", resolution = "resolution [ширина высота] — экран",
    sleep = "sleep <секунды> — пауза", wget = "wget [-f] <URL> [файл] — скачать HTTP(S) через интернет-карту"
  }
  putLine(pages[args[1]] or (commands[args[1]] and (args[1] .. " — встроенная команда AstraOS") or "страница не найдена"))
end
commands.sleep = function(args)
  local duration = tonumber(args[1])
  if not duration or duration < 0 then putLine("Использование: sleep <секунды>", 0xFFCC66); return end
  computer.pullSignal(math.min(duration, 3600))
end
commands.resolution = function(args)
  if not args[1] then
    local w, h = gpu.getResolution()
    putLine(string.format("%d x %d", w, h)); return
  end
  local w, h = tonumber(args[1]), tonumber(args[2])
  if not w or not h then putLine("Использование: resolution [ширина высота]", 0xFFCC66); return end
  local ok, result, reason = pcall(gpu.setResolution, w, h)
  if ok and result then
    width, height = gpu.getResolution()
    clearScreen()
    putLine(string.format("Разрешение: %d x %d", width, height), ACCENT)
  else
    putLine("resolution: " .. tostring(ok and reason or result), 0xFF6666)
  end
end
commands.wget = function(args)
  local force, i = false, 1
  while args[i] and args[i]:sub(1, 1) == "-" and args[i] ~= "-" do
    if args[i] == "--force" then force = true
    elseif args[i] == "--" then i = i + 1; break
    else
      for flag in args[i]:sub(2):gmatch(".") do
        if flag == "f" then force = true
        else putLine("wget: неизвестная опция -" .. flag, 0xFF6666); return end
      end
    end
    i = i + 1
  end
  local url = args[i]
  if not url then putLine("Использование: wget [-f] <URL> [файл]", 0xFFCC66); return end
  local destination = args[i + 1]
  if not destination then
    local remotePath = url:match("^https?://[^/]+/([^?#]+)")
    destination = remotePath and remotePath:match("([^/]+)$")
  end
  if not destination or destination == "" then putLine("wget: укажи имя локального файла", 0xFF6666); return end
  destination = normalize(destination)
  local existsOk, destinationExists = pcall(fs.exists, destination)
  if existsOk and destinationExists and not force then putLine("wget: файл уже существует (используй -f)", 0xFF6666); return end
  local temporary, backup = destination .. ".astraos-part", destination .. ".astraos-wget-backup"
  if fs.exists(backup) then putLine("wget: уже существует резервная копия " .. backup, 0xFF6666); return end
  if fs.exists(temporary) then pcall(fs.remove, temporary) end

  local internetAddress = component.list("internet", true)()
  if not internetAddress then putLine("wget: интернет-карта не найдена", 0xFF6666); return end
  local proxyOk, net = pcall(component.proxy, internetAddress)
  if not proxyOk or not net then putLine("wget: не удалось открыть интернет-карту", 0xFF6666); return end
  if net.isHttpEnabled then
    local httpOk, enabled = pcall(net.isHttpEnabled)
    if httpOk and not enabled then putLine("wget: HTTP отключён в настройках OpenComputers", 0xFF6666); return end
  end
  local request, requestError = net.request(url)
  if not request then putLine("wget: " .. tostring(requestError or "запрос не выполнен"), 0xFF6666); return end
  local output, openError = fs.open(temporary, "w")
  if not output then pcall(request.close); putLine("wget: " .. tostring(openError or "не удалось создать файл"), 0xFF6666); return end

  putLine("Скачиваю " .. url .. " ...", MUTED)
  local received, failure = 0, nil
  while true do
    local readOk, chunk, readError = pcall(request.read)
    if not readOk then failure = chunk; break end
    if chunk == nil then
      if readError then failure = readError end
      break
    elseif #chunk > 0 then
      local writeOk, writeError = fs.write(output, chunk)
      if not writeOk then failure = writeError or "ошибка записи"; break end
      received = received + #chunk
    else
      computer.pullSignal(0.05)
    end
  end
  pcall(request.close)
  pcall(fs.close, output)
  if failure then
    pcall(fs.remove, temporary)
    putLine("wget: загрузка не удалась: " .. tostring(failure), 0xFF6666)
    return
  end
  local backedUp = false
  if destinationExists then
    local moved, moveError = fs.rename(destination, backup)
    if not moved then pcall(fs.remove, temporary); putLine("wget: не удалось сохранить старый файл: " .. tostring(moveError), 0xFF6666); return end
    backedUp = true
  end
  local moved, moveError = fs.rename(temporary, destination)
  if not moved then
    if backedUp then pcall(fs.rename, backup, destination) end
    pcall(fs.remove, temporary)
    putLine("wget: не удалось установить скачанный файл: " .. tostring(moveError), 0xFF6666)
    return
  end
  if backedUp then pcall(fs.remove, backup) end
  putLine("Сохранено: " .. destination .. " (" .. formatBytes(received) .. ")", ACCENT)
end
commands.date = function() putLine(os.date("%Y-%m-%d %H:%M:%S")) end
commands.reboot = function() putLine("Перезагрузка..."); computer.shutdown(true) end
commands.shutdown = function() putLine("Выключение..."); computer.shutdown() end
commands.exit = function() putLine("Это системная оболочка; для выключения используй shutdown.", MUTED) end

local function executeWords(words, depth)
  if #words == 0 then return end
  depth = depth or 0
  local name = words[1]
  if aliases[name] then
    if depth >= 8 then putLine("alias: превышена глубина раскрытия", 0xFF6666); return end
    local expanded = {}
    for _, token in ipairs(aliases[name]) do expanded[#expanded + 1] = token end
    for i = 2, #words do expanded[#expanded + 1] = words[i] end
    return executeWords(expanded, depth + 1)
  end
  table.remove(words, 1)
  local fn = commands[name]
  if fn then
    local ok, err = pcall(fn, words)
    if not ok then putLine("Ошибка команды: " .. tostring(err), 0xFF6666) end
    return
  end
  local script = normalize("/bin/" .. name .. ".lua")
  local existsOk, exists = pcall(fs.exists, script)
  if existsOk and exists then runLua(script, words)
  else putLine("Команда не найдена: " .. name .. " (help)", 0xFF6666) end
end

local function execute(line)
  executeWords(parse(line), 0)
end

clearScreen()
putLine("AstraOS 0.2", ACCENT)
putLine("Независимая минимальная система для OpenComputers", MUTED)
putLine("Введите help для списка команд. Загрузочный диск: " .. tostring(bootAddress or "авто"))
putLine("")
while true do
  local prompt = "astra:" .. cwd .. "$ "
  local line = readLine(prompt)
  if line ~= "" then
    history[#history + 1] = line
    if #history > 20 then table.remove(history, 1) end
    historyIndex = #history + 1
    execute(line)
  end
end
