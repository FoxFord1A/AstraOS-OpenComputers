-- AstraOS 0.1 - small standalone shell OS for OpenComputers.
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

local function cmdHelp()
  putLine("AstraOS — команды:", ACCENT)
  putLine("help clear about pwd ls cd cat echo mkdir touch rm cp mv edit lua", MUTED)
  putLine("sysinfo components date reboot shutdown", MUTED)
  putLine("Пути абсолютные (/home/file) или относительно текущего каталога.")
end

local commands = {}
commands.help = cmdHelp
commands.clear = function() clearScreen() end
commands.cls = commands.clear
commands.about = function()
  putLine("AstraOS 0.1 — компактная ОС для OpenComputers", ACCENT)
  putLine("Lua BIOS напрямую; без библиотек OpenOS. Загружена с " .. tostring(bootAddress or "авто-носителя"))
end
commands.pwd = function() putLine(cwd) end
commands.ls = function(args)
  local path = normalize(args[1] or ".")
  local entries, reason = listDirectory(path)
  if not entries then putLine("ls: " .. tostring(reason), 0xFF6666); return end
  if #entries == 0 then putLine("(пусто)", MUTED); return end
  for _, entry in ipairs(entries) do putLine(entry) end
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
  if not args[1] then putLine("Использование: mkdir <каталог>", 0xFFCC66); return end
  local ok, result = pcall(fs.makeDirectory, normalize(args[1]))
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
  if not args[1] then putLine("Использование: rm <файл|каталог>", 0xFFCC66); return end
  local path = normalize(args[1])
  if path == "/" or path == "/init.lua" or path == "/system" or path:sub(1, 8) == "/system/" then
    putLine("rm: защищён системный путь " .. path, 0xFF6666); return
  end
  local ok, result = pcall(fs.remove, path)
  if not ok or not result then putLine("rm: не удалось удалить " .. path, 0xFF6666) end
end
local function copyPath(source, destination)
  local src, reason = readFile(source)
  if not src then return nil, reason end
  local isDirOk, isDir = pcall(fs.isDirectory, destination)
  if isDirOk and isDir then destination = normalize(destination .. "/" .. basename(source)) end
  return writeFile(destination, src)
end
commands.cp = function(args)
  if not args[1] or not args[2] then putLine("Использование: cp <источник> <назначение>", 0xFFCC66); return end
  local ok, reason = copyPath(normalize(args[1]), normalize(args[2]))
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
  putLine("AstraOS 0.1 | Lua " .. tostring(_VERSION), ACCENT)
  putLine("CPU: " .. safe(computer.address))
  putLine("RAM: " .. safe(computer.freeMemory) .. " / " .. safe(computer.totalMemory) .. " байт")
  putLine("Энергия: " .. safe(computer.energy) .. " / " .. safe(computer.maxEnergy))
  putLine("Время работы: " .. safe(computer.uptime) .. " с")
  putLine("Загрузочный FS: " .. tostring(bootAddress or "не указан"))
end
commands.components = function()
  for address, kind in component.list() do putLine(kind .. "  " .. address) end
end
commands.date = function() putLine(os.date("%Y-%m-%d %H:%M:%S")) end
commands.reboot = function() putLine("Перезагрузка..."); computer.shutdown(true) end
commands.shutdown = function() putLine("Выключение..."); computer.shutdown() end
commands.exit = function() putLine("Это системная оболочка; для выключения используй shutdown.", MUTED) end

local function execute(line)
  local words = parse(line)
  if #words == 0 then return end
  local name = table.remove(words, 1)
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

clearScreen()
putLine("AstraOS 0.1", ACCENT)
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
