--[[
    Better Movement Speed for RE9 Requiem

    Requires: REFramework
--]]

local MOD_NAME = "[Better Movement Speed]"
local CONFIG_PATH = "re9_movement_speed.json"
local DEFAULT_SPEED = 1.0

local cfg = {
    enabled = true,
    grace = { walk_speed = 1.3, run_speed = 1.3 },
    leon  = { walk_speed = 1.3, run_speed = 1.3 },
}

local function load_config()
    if not json or not json.load_file then return end
    local ok, d = pcall(json.load_file, CONFIG_PATH)
    if ok and type(d) == "table" then
        if type(d.enabled) == "boolean" then cfg.enabled = d.enabled end
        for _, key in ipairs({"grace", "leon"}) do
            if type(d[key]) == "table" then
                if type(d[key].walk_speed) == "number" then cfg[key].walk_speed = d[key].walk_speed end
                if type(d[key].run_speed) == "number" then cfg[key].run_speed = d[key].run_speed end
            end
        end
        -- migrate old flat config
        if type(d.walk_speed) == "number" and not d.grace then
            cfg.grace.walk_speed = d.walk_speed
            cfg.grace.run_speed = d.run_speed or d.walk_speed
            cfg.leon.walk_speed = d.walk_speed
            cfg.leon.run_speed = d.run_speed or d.walk_speed
        end
    end
end

local function save_config()
    if json and json.dump_file then pcall(json.dump_file, CONFIG_PATH, cfg) end
end

local function get_layer0()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local ctx = cm:call("getPlayerContextRef")
    if not ctx then return nil end
    local go = ctx:call("get_GameObject")
    if not go then return nil end
    local motion = go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
    if not motion then return nil end
    return motion:call("getLayer", 0)
end

-- Returns: character ("grace"/"leon"/nil), move_type ("walk"/"run"/nil)
local function get_motion_info()
    local layer = get_layer0()
    if not layer then return nil, nil end
    local node = layer:call("get_HighestWeightMotionNode")
    if not node then return nil, nil end
    local name = node:call("get_MotionName")
    if not name then return nil, nil end

    local lower = name:lower()

    -- skip combat animations
    if lower:find("attack") or lower:find("finish") or lower:find("execution") then
        return nil, nil
    end

    -- character
    local character = nil
    if lower:find("ch0200") then
        character = "grace"
    elseif lower:find("ch0100") then
        character = "leon"
    end

    -- move type
    local move_type = nil
    if lower:find("walk") then
        move_type = "walk"
    elseif lower:find("run") then
        move_type = "run"
    end

    return character, move_type
end

local function set_layer_speed(speed)
    local layer = get_layer0()
    if layer then layer:call("set_Speed", speed) end
end

-- patch internal move speed so 1st-person camera keeps up with animation
local current_speed_factor = DEFAULT_SPEED
do
    local td = sdk.find_type_definition("app.MovementDriver")
    local m = td and td:get_method("getMoveSpeed")
    if m then
        sdk.hook(m, nil, function(ret)
            if not cfg.enabled or current_speed_factor == DEFAULT_SPEED then return ret end
            local v = sdk.to_float(ret)
            return v and sdk.float_to_ptr(v * current_speed_factor) or ret
        end)
    end
end

pcall(load_config)

re.on_pre_application_entry("LateUpdateBehavior", function()
    if not cfg.enabled then
        current_speed_factor = DEFAULT_SPEED
        set_layer_speed(DEFAULT_SPEED)
        return
    end
    local ok, character, move_type = pcall(get_motion_info)
    if not ok then return end

    if character and move_type then
        local char_cfg = cfg[character]
        local spd = (move_type == "walk") and char_cfg.walk_speed or char_cfg.run_speed
        current_speed_factor = spd
        set_layer_speed(spd)
    else
        current_speed_factor = DEFAULT_SPEED
        set_layer_speed(DEFAULT_SPEED)
    end
end)

re.on_draw_ui(function()
    if not imgui or not imgui.tree_node(MOD_NAME) then return end
    local changed = false
    local c, v

    c, v = imgui.checkbox("Enable", cfg.enabled)
    if c then cfg.enabled = v; changed = true; if not v then current_speed_factor = DEFAULT_SPEED; set_layer_speed(DEFAULT_SPEED) end end

    imgui.separator()
    imgui.text("-- Grace --")
    c, v = imgui.slider_float("Walk Speed##grace", cfg.grace.walk_speed, 0.5, 3.0, "%.2f")
    if c then cfg.grace.walk_speed = v; changed = true end
    c, v = imgui.slider_float("Run Speed##grace", cfg.grace.run_speed, 0.5, 3.0, "%.2f")
    if c then cfg.grace.run_speed = v; changed = true end

    imgui.separator()
    imgui.text("-- Leon --")
    c, v = imgui.slider_float("Walk Speed##leon", cfg.leon.walk_speed, 0.5, 3.0, "%.2f")
    if c then cfg.leon.walk_speed = v; changed = true end
    c, v = imgui.slider_float("Run Speed##leon", cfg.leon.run_speed, 0.5, 3.0, "%.2f")
    if c then cfg.leon.run_speed = v; changed = true end

    if changed then save_config() end
    imgui.tree_pop()
end)

re.on_script_reset(function()
    current_speed_factor = DEFAULT_SPEED
    set_layer_speed(DEFAULT_SPEED)
end)
re.on_config_save(save_config)
