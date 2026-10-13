local root = arg[1]
local callbacks, payloads = {}, {}
local state_home = assert(os.getenv("XDG_STATE_HOME"))
local catalog_path = state_home .. "/omarchy/omakeez/bridge-catalog.lua"
local catalog_seed = state_home .. "/omarchy/omakeez/bridge-catalog.seed.lua"
hl = {
  on = function(name, callback)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], callback)
  end,
  dsp = { event = function(value) return value end },
  dispatch = function(value) payloads[#payloads + 1] = value end,
}
X = function(name, event)
  assert(callbacks[name], "missing callback: " .. name)
  for _, callback in ipairs(callbacks[name]) do callback(event) end
end
-- A pre-rebrand bridge state must never prevent Omakeez from registering its
-- own callbacks in the same Hyprland Lua session.
_G.__keybind_dojo_bridge_state = { enabled = true }
assert(pcall(dofile, root .. "/bridge.lua"))
local function registration_count()
  local count = 0
  for _, registrations in pairs(callbacks) do count = count + #registrations end
  return count
end
-- Loading before generation finishes must fail closed without installing
-- callbacks. A later real Hyprland reload retries once at config evaluation.
assert(registration_count() == 0)
assert(os.rename(catalog_seed, catalog_path))
assert(pcall(dofile, root .. "/bridge.lua"))
local count = registration_count()
assert(count == 2)
assert(#callbacks["input.keyboard.key"] == 1)
assert(#callbacks["keybinds.submap"] == 1)
X("input.keyboard.key", { keycode = 133, state = 1 })
assert(payloads[1] == "omakeez:v1:guide:down:SUPER")
X("input.keyboard.key", { keycode = 133, state = 1 })
X("input.keyboard.key", { keycode = 36, state = 1 })
X("input.keyboard.key", { keycode = 36, state = 0 })
X("keybinds.submap", "resize")
X("input.keyboard.key", { keycode = 20, state = 1 })
X("input.keyboard.key", { keycode = 133, state = 0 })
assert(payloads[1] == "omakeez:v1:guide:down:SUPER")
assert(payloads[2]:match(":match:sha256:a") ~= nil)
assert(payloads[3]:match(":match:sha256:b") ~= nil)
assert(payloads[4]:match(":match:sha256:c") ~= nil)
assert(payloads[5] == "omakeez:v1:guide:up")
X("input.keyboard.key", { keycode = 64, state = 1 })
X("input.keyboard.key", { keycode = 50, state = 1 })
X("input.keyboard.key", { keycode = 50, state = 0 })
X("input.keyboard.key", { keycode = 64, state = 0 })
assert(payloads[6] == "omakeez:v1:guide:down:ALT")
assert(payloads[7] == "omakeez:v1:mods:SHIFT_ALT")
assert(payloads[8] == "omakeez:v1:mods:ALT")
assert(payloads[9] == "omakeez:v1:guide:up")
for _ = 1, 10000 do X("input.keyboard.key", { keycode = 10, state = 1 }) end
assert(#payloads == 9)
-- A live Hyprland reload re-evaluates bridge.lua. It must replace the
-- in-memory snapshot while keeping exactly one subscription per event.
local catalog_file = assert(io.open(catalog_path, "r"))
local catalog_text = catalog_file:read("*a")
catalog_file:close()
local removed_line = '    ["SUPER|36|press|"] = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",\n'
local start, finish = catalog_text:find(removed_line, 1, true)
assert(start, "fixture binding to remove was not found")
local removed = catalog_text:sub(1, start - 1) .. catalog_text:sub(finish + 1)
local updated, updated_count = removed:gsub("sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
assert(updated_count == 1)
local updated_file = assert(io.open(catalog_path, "w"))
updated_file:write(updated)
updated_file:close()
assert(pcall(dofile, root .. "/bridge.lua"))
assert(registration_count() == count)
assert(#callbacks["input.keyboard.key"] == 1)
assert(#callbacks["keybinds.submap"] == 1)
local refreshed = assert(_G.__omakeez_bridge_state)
assert(refreshed.catalog.matches["SUPER|36|press|"] == nil)
assert(refreshed.catalog.matches["SUPER|20|press|resize"] == "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
assert(refreshed.guideRoot == nil and refreshed.submap == "")
X("input.keyboard.key", { keycode = 133, state = 1 })
X("input.keyboard.key", { keycode = 36, state = 1 })
assert(#payloads == 10)
assert(payloads[10] == "omakeez:v1:guide:down:SUPER")
X("input.keyboard.key", { keycode = 133, state = 0 })
X("keybinds.submap", "resize")
X("input.keyboard.key", { keycode = 133, state = 1 })
X("input.keyboard.key", { keycode = 20, state = 1 })
assert(payloads[13]:match(":match:sha256:d") ~= nil)

-- A malformed replacement disables the existing bridge snapshot. Ordinary
-- keys then remain inert; file access is retried only by another Lua reload.
local invalid_file = assert(io.open(catalog_path, "w"))
invalid_file:write("return {}\n")
invalid_file:close()
assert(pcall(dofile, root .. "/bridge.lua"))
assert(not refreshed.enabled)
assert(registration_count() == count)
local payload_count = #payloads
for _ = 1, 10000 do X("input.keyboard.key", { keycode = 10, state = 1 }) end
assert(#payloads == payload_count)

local restore_file = assert(io.open(catalog_path, "w"))
restore_file:write(updated)
restore_file:close()
assert(pcall(dofile, root .. "/bridge.lua"))
assert(refreshed.enabled)
assert(registration_count() == count)

local before = registration_count()
assert(pcall(dofile, root .. "/bridge.lua"))
local after = registration_count()
assert(before == after)
