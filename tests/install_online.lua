-- Host-side integration test for install-online.lua.
-- Run with: lua tests/install_online.lua .
local root = (arg and arg[1]) or "."
root = root:gsub("/$", "")
local function loadText(path)
  local f = assert(io.open(root .. path, "rb"))
  local value = f:read("*a")
  f:close()
  return value
end

local files = {
  ["/init.lua"] = "old OpenOS boot file",
  ["/system/main.lua"] = "old kernel"
}
local handles, nextHandle = {}, 0
local fakeFs = {}
fakeFs.isReadOnly = function() return false end
fakeFs.getLabel = function() return "Test Disk" end
fakeFs.exists = function(path) return files[path] ~= nil or path == "/system" end
fakeFs.isDirectory = function(path) return path == "/system" end
fakeFs.makeDirectory = function(path) return path == "/system" end
fakeFs.rename = function(oldPath, newPath)
  if not files[oldPath] or files[newPath] then return false, "rename conflict" end
  files[newPath], files[oldPath] = files[oldPath], nil
  return true
end
fakeFs.remove = function(path) files[path] = nil; return true end
fakeFs.open = function(path, mode)
  if mode == "w" then
    nextHandle = nextHandle + 1
    handles[nextHandle] = {path = path, data = ""}
    return nextHandle
  end
  return nil, "unsupported mode"
end
fakeFs.write = function(handle, data)
  handles[handle].data = handles[handle].data .. data
  return true
end
fakeFs.close = function(handle)
  local stream = handles[handle]
  if stream then files[stream.path] = stream.data; handles[handle] = nil end
  return true
end

component = {
  isAvailable = function(kind) return kind == "internet" end,
  list = function(kind, exact)
    if kind ~= "filesystem" or not exact then return function() return nil end end
    local yielded = false
    return function()
      if yielded then return nil end
      yielded = true
      return "test-disk", "filesystem"
    end
  end,
  proxy = function(address)
    assert(address == "test-disk")
    return fakeFs
  end
}
computer = {tmpAddress = function() return nil end}
internet = {
  request = function(url)
    local body
    if url:match("/init.lua$") then body = loadText("/init.lua")
    elseif url:match("/system/main.lua$") then body = loadText("/system/main.lua")
    else error("unexpected URL: " .. url) end
    local yielded = false
    return function()
      if yielded then return nil end
      yielded = true
      return body
    end
  end
}

local input = {"1", "INSTALL"}
local inputIndex, output = 0, {}
local fakeIO = {
  write = function(...)
    local values = {...}
    for i = 1, #values do output[#output + 1] = tostring(values[i]) end
    return fakeIO
  end,
  read = function()
    inputIndex = inputIndex + 1
    return input[inputIndex]
  end,
  stderr = {write = function(...) end}
}
local env = setmetatable({
  component = component,
  computer = computer,
  internet = internet,
  io = fakeIO,
  require = function(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    if name == "internet" then return internet end
    error("unexpected require: " .. name)
  end
}, {__index = _G})

local installer, loadError = loadfile(root .. "/install-online.lua", "t", env)
assert(installer, loadError)
installer()
assert(files["/init.lua"] == loadText("/init.lua"), "new BIOS entry point was not installed")
assert(files["/system/main.lua"] == loadText("/system/main.lua"), "new kernel was not installed")
assert(files["/init.lua.astraos-backup"] == "old OpenOS boot file", "old init.lua was not backed up")
assert(files["/system/main.lua.astraos-backup"] == "old kernel", "old kernel was not backed up")
assert(table.concat(output):find("AstraOS установлена", 1, true), "success message was not printed")
print("PASS: online installer downloaded, validated, backed up and installed AstraOS.")
