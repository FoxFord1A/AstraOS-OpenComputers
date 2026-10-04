-- Host-side smoke test for AstraOS bootstrap. Run with: lua tests/smoke.lua .
local root = (arg and arg[1]) or "."
root = root:gsub("/$", "")
local drawn, handles, nextHandle = {}, {}, 0
local files = {}

files.exists = function(path)
  local file = io.open(root .. path, "rb")
  if not file then return false end
  file:close()
  return true
end
files.open = function(path, mode)
  local file, reason = io.open(root .. path, mode == "w" and "wb" or "rb")
  if not file then return nil, reason end
  nextHandle = nextHandle + 1
  handles[nextHandle] = file
  return nextHandle
end
files.read = function(handle, count) return handles[handle]:read(count) end
files.write = function(handle, data) return handles[handle]:write(data) ~= nil end
files.close = function(handle)
  if handles[handle] then handles[handle]:close(); handles[handle] = nil end
  return true
end
files.isDirectory = function(path) return path == "/" or path == "/system" end
files.list = function() return {} end

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
  local all = { {"fsaddr", "filesystem"}, {"gpuaddr", "gpu"}, {"screenaddr", "screen"} }
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
  error("unknown component " .. tostring(address))
end

local signals = {}
local command = "about"
for i = 1, #command do signals[#signals + 1] = {"key_down", "keyboard", command:byte(i), 0} end
signals[#signals + 1] = {"key_down", "keyboard", 0, 28}
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
if not screenText:find("AstraOS 0.1", 1, true) then print("Captured GPU output:\n" .. screenText) end
assert(screenText:find("AstraOS 0.1", 1, true), "boot banner was not rendered")
assert(screenText:find("компактная ОС", 1, true), "about command did not run")
print("PASS: BIOS bootstrap found the disk, loaded the kernel, rendered the shell and executed `about`.")
