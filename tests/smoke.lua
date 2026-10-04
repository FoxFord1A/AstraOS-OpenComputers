-- Host-side smoke test for AstraOS bootstrap. Run with: lua tests/smoke.lua .
local root = (arg and arg[1]) or "."
root = root:gsub("/$", "")
local drawn, handles, nextHandle = {}, {}, 0
local files, memoryFiles = {}, {}

files.exists = function(path)
  if memoryFiles[path] ~= nil then return true end
  local file = io.open(root .. path, "rb")
  if not file then return false end
  file:close()
  return true
end
files.open = function(path, mode)
  if path:sub(1, 9) == "/virtual/" and mode == "w" then
    nextHandle = nextHandle + 1
    handles[nextHandle] = {virtual = path, data = ""}
    return nextHandle
  end
  local file, reason = io.open(root .. path, mode == "w" and "wb" or "rb")
  if not file then return nil, reason end
  nextHandle = nextHandle + 1
  handles[nextHandle] = file
  return nextHandle
end
files.read = function(handle, count) return handles[handle]:read(count) end
files.write = function(handle, data)
  if type(handles[handle]) == "table" then handles[handle].data = handles[handle].data .. data; return true end
  return handles[handle]:write(data) ~= nil
end
files.close = function(handle)
  if type(handles[handle]) == "table" then
    memoryFiles[handles[handle].virtual] = handles[handle].data
    handles[handle] = nil
  elseif handles[handle] then handles[handle]:close(); handles[handle] = nil end
  return true
end
files.isDirectory = function(path) return path == "/" or path == "/system" end
files.list = function(path)
  if path == "/" then return {"init.lua", "system/"} end
  if path == "/system" then return {"main.lua"} end
  return {}
end
files.size = function(path)
  if memoryFiles[path] ~= nil then return #memoryFiles[path] end
  local file = assert(io.open(root .. path, "rb"))
  local size = file:seek("end")
  file:close()
  return size
end
files.spaceUsed = function() return 4096 end
files.spaceTotal = function() return 65536 end
files.getLabel = function() return "Smoke Disk" end
files.remove = function(path) memoryFiles[path] = nil; return true end
files.rename = function(oldPath, newPath)
  if memoryFiles[oldPath] == nil or memoryFiles[newPath] ~= nil then return false end
  memoryFiles[newPath], memoryFiles[oldPath] = memoryFiles[oldPath], nil
  return true
end

local gpu = {}
gpu.bind = function() return true end
gpu.getResolution = function() return 80, 25 end
gpu.setBackground = function() end
gpu.setForeground = function() end
gpu.fill = function() end
gpu.copy = function() end
gpu.set = function(_, _, text) drawn[#drawn + 1] = tostring(text); return true end

component = {}
component.list = function(filter, exact)
  local all = { {"fsaddr", "filesystem"}, {"gpuaddr", "gpu"}, {"screenaddr", "screen"}, {"netaddr", "internet"} }
  local found = {}
  for _, item in ipairs(all) do
    if not filter or (exact and item[2] == filter) or (not exact and item[2]:find(filter, 1, true)) then
      found[#found + 1] = item
    end
  end
  local i = 0
  return function()
    i = i + 1
    if found[i] then return found[i][1], found[i][2] end
  end
end
component.proxy = function(address)
  if address == "fsaddr" then return files end
  if address == "gpuaddr" then return gpu end
  if address == "screenaddr" then return { address = address, type = "screen" } end
  if address == "netaddr" then
    local chunks, index = {"Astra", "OS\n"}, 0
    return {
      isHttpEnabled = function() return true end,
      request = function(url)
        assert(url == "https://example.test/payload")
        return {
          read = function()
            index = index + 1
            return chunks[index]
          end,
          close = function() return true end
        }
      end
    }
  end
  error("unknown component " .. tostring(address))
end

local signals = {}
local commands = {"about", "free", "uptime", "which ls", "df", "du /system/main.lua", "head -n 1 /system/main.lua", "tail -n 1 /system/main.lua", "tree /", "find / main.lua", "wc /system/main.lua", "grep AstraOS /system/main.lua", "man grep", "rm -r /system", "cp /system /tmp", "wget https://example.test/payload /virtual/payload.txt", "alias hi echo hello", "hi world"}
for _, command in ipairs(commands) do
  for i = 1, #command do signals[#signals + 1] = {"key_down", "keyboard", command:byte(i), 0} end
  signals[#signals + 1] = {"key_down", "keyboard", 0, 28}
end
local signalIndex = 0
computer = {
  getBootAddress = function() return "fsaddr" end,
  pullSignal = function()
    signalIndex = signalIndex + 1
    local event = signals[signalIndex]
    if event then return table.unpack(event) end
    error("TEST_STOP")
  end,
  beep = function() end,
  address = function() return "computer-address" end,
  freeMemory = function() return 32768 end,
  totalMemory = function() return 65536 end,
  energy = function() return 100 end,
  maxEnergy = function() return 100 end,
  uptime = function() return 1 end
}
unicode = {
  char = function(codepoint) return string.char(codepoint) end,
  wlen = function(text) return #text end,
  len = function(text) return #text end,
  sub = function(text, first, last) return text:sub(first, last) end
}

local boot, loadError = loadfile(root .. "/init.lua")
assert(boot, loadError)
local ok, err = pcall(boot)
assert(not ok and tostring(err):find("TEST_STOP", 1, true), "test sentinel did not stop the OS loop")
local screenText = table.concat(drawn, "\n")
assert(screenText:find("AstraOS 0.2", 1, true), "boot banner was not rendered")
assert(screenText:find("компактная ОС", 1, true), "about command did not run")
assert(screenText:find("RAM свободно", 1, true), "free command did not run")
assert(screenText:find("встроенная команда", 1, true), "which command did not run")
assert(screenText:find("Smoke Disk", 1, true), "df command did not run")
assert(screenText:find("main.lua", 1, true), "tree/find/head/tail commands did not run")
assert(screenText:find("hello world", 1, true), "alias expansion did not run")
assert(screenText:find("AstraOS 0.2 | Lua", 1, true), "grep command did not return a match")
assert(screenText:find("защищён системный путь", 1, true), "rm did not protect system files")
assert(screenText:find("используй cp -r", 1, true), "cp did not require -r for directories")
assert(memoryFiles["/virtual/payload.txt"] == "AstraOS\n", "wget did not download the HTTP response")
print("PASS: BIOS booted AstraOS, rendered the shell and ran OpenOS-style utilities and aliases.")
