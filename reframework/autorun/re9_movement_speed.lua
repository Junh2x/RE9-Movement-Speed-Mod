-- Better Movement Speed by junhx2

local MOD_NAME = "[Better Movement Speed]"
local CONFIG_PATH = "re9_movement_speed.json"
local DEFAULT_SPEED = 1.0

local motion_type = sdk.typeof("via.motion.Motion")
local modified_layers = {}
local enemy_skip_keywords = { "attack", "finish", "execution", "dead", "death", "damage", "grapple", "stun", "down" }
local enemy_exclude_types = { "B030", "V000", "V100" }

local function safe_call(obj, method, ...)
    if not obj then return nil end
    local ok, ret = pcall(obj.call, obj, method, ...)
    if ok then return ret end
    return nil
end

local function get_enemy_category(ctx)
    if not ctx then return nil end
    local ok, td = pcall(ctx.get_type_definition, ctx)
    if not ok or not td then return nil end
    local ok2, name = pcall(td.get_full_name, td)
    if not ok2 or not name then return nil end
    for _, ex in ipairs(enemy_exclude_types) do
        if name:find(ex) then return nil end
    end
    if name:find("B800") then return "b800" end
    return "enemy"
end

local function get_enemy_move_type(anim_name)
    if not anim_name then return nil end
    local lower = anim_name:lower()
    for _, kw in ipairs(enemy_skip_keywords) do
        if lower:find(kw) then return nil end
    end
    if lower:find("walk") then return "walk" end
    if lower:find("run") then return "run" end
    return nil
end

-- Characters
local CHARACTERS = {
    { key = "grace", label = "Grace", pattern = "ch0200" },
    { key = "leon",  label = "Leon",  pattern = "ch0100" },
    { key = "chloe", label = "Chloe", pattern = "ch0300" },
}

local function default_char_speed()
    return { walk_speed = 1.3, run_speed = 1.3 }
end

-- Config
local cfg = {
    enabled = true,
    enemy_enabled = false,
    enemies  = { walk_speed = 1.0, run_speed = 1.0 },
    the_girl = { walk_speed = 1.0, run_speed = 1.0 },
}
for _, ch in ipairs(CHARACTERS) do
    cfg[ch.key] = default_char_speed()
end

local function load_config()
    if not json or not json.load_file then return end
    local ok, d = pcall(json.load_file, CONFIG_PATH)
    if not ok or type(d) ~= "table" then return end

    if type(d.enabled) == "boolean" then cfg.enabled = d.enabled end

    for _, ch in ipairs(CHARACTERS) do
        if type(d[ch.key]) == "table" then
            if type(d[ch.key].walk_speed) == "number" then cfg[ch.key].walk_speed = d[ch.key].walk_speed end
            if type(d[ch.key].run_speed) == "number" then cfg[ch.key].run_speed = d[ch.key].run_speed end
        end
    end

    if type(d.enemy_enabled) == "boolean" then cfg.enemy_enabled = d.enemy_enabled end
    for _, key in ipairs({"enemies", "the_girl"}) do
        if type(d[key]) == "table" then
            if type(d[key].walk_speed) == "number" then cfg[key].walk_speed = d[key].walk_speed end
            if type(d[key].run_speed) == "number" then cfg[key].run_speed = d[key].run_speed end
        end
    end

    if type(d.walk_speed) == "number" and not d.grace then
        for _, ch in ipairs(CHARACTERS) do
            cfg[ch.key].walk_speed = d.walk_speed
            cfg[ch.key].run_speed = d.run_speed or d.walk_speed
        end
    end
end

local function save_config()
    if json and json.dump_file then pcall(json.dump_file, CONFIG_PATH, cfg) end
end

-- Player speed
local function get_layer0()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local ctx = cm:call("getPlayerContextRef")
    if not ctx then return nil end
    local go = ctx:call("get_GameObject")
    if not go then return nil end
    local motion = go:call("getComponent(System.Type)", motion_type)
    if not motion then return nil end
    return motion:call("getLayer", 0)
end

local function get_motion_info()
    local layer = get_layer0()
    if not layer then return nil, nil end
    local node = layer:call("get_HighestWeightMotionNode")
    if not node then return nil, nil end
    local name = node:call("get_MotionName")
    if not name then return nil, nil end

    local lower = name:lower()

    if lower:find("attack") or lower:find("finish") or lower:find("execution") then
        return nil, nil
    end

    local character = nil
    for _, ch in ipairs(CHARACTERS) do
        if lower:find(ch.pattern) then
            character = ch.key
            break
        end
    end

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

local current_speed_factor = DEFAULT_SPEED

local function reset_speed()
    current_speed_factor = DEFAULT_SPEED
    set_layer_speed(DEFAULT_SPEED)
end

-- Enemy speed
local function reset_enemy_speeds()
    for layer, _ in pairs(modified_layers) do
        pcall(layer.call, layer, "set_Speed", DEFAULT_SPEED)
    end
    modified_layers = {}
end

local function update_enemy_speeds()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return end
    local list = safe_call(cm, "get_EnemyContextList")
    if not list then return end
    local ok_c, count = pcall(function() return list:call("get_Count") end)
    if not ok_c or not count or count == 0 then return end

    for i = 0, count - 1 do
        local ok_i, ctx = pcall(function() return list:call("get_Item", i) end)
        if not ok_i or not ctx then goto continue end

        local category = get_enemy_category(ctx)
        if not category then goto continue end

        local go = safe_call(ctx, "get_GameObject")
        if not go then goto continue end

        local motion = safe_call(go, "getComponent(System.Type)", motion_type)
        if not motion then goto continue end

        local layer0 = safe_call(motion, "getLayer", 0)
        if not layer0 then goto continue end

        local node = safe_call(layer0, "get_HighestWeightMotionNode")
        local anim_name = node and safe_call(node, "get_MotionName") or nil
        local move_type = get_enemy_move_type(anim_name)

        local hp_obj = safe_call(ctx, "get_HitPoint")
        local cur_hp = hp_obj and safe_call(hp_obj, "get_CurrentHitPoint") or nil
        local is_dead = (cur_hp and cur_hp <= 0)

        if not is_dead then
            if move_type then
                local speed_cfg = (category == "b800") and cfg.the_girl or cfg.enemies
                local spd_val = (move_type == "walk") and speed_cfg.walk_speed or speed_cfg.run_speed
                pcall(layer0.call, layer0, "set_Speed", spd_val)
                modified_layers[layer0] = true
            else
                if modified_layers[layer0] then
                    pcall(layer0.call, layer0, "set_Speed", DEFAULT_SPEED)
                    modified_layers[layer0] = nil
                end
            end
        end

        ::continue::
    end
end

-- 1st-person camera sync
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

-- Init
pcall(load_config)

-- Update
re.on_pre_application_entry("LateUpdateBehavior", function()
    if cfg.enabled then
        local ok, character, move_type = pcall(get_motion_info)
        if ok and character and move_type then
            local spd = (move_type == "walk") and cfg[character].walk_speed or cfg[character].run_speed
            current_speed_factor = spd
            set_layer_speed(spd)
        else
            reset_speed()
        end
    else
        reset_speed()
    end

    if cfg.enemy_enabled then
        local all_default = cfg.enemies.walk_speed == 1.0 and cfg.enemies.run_speed == 1.0
            and cfg.the_girl.walk_speed == 1.0 and cfg.the_girl.run_speed == 1.0
        if not all_default or next(modified_layers) then
            pcall(update_enemy_speeds)
        end
    else
        if next(modified_layers) then reset_enemy_speeds() end
    end
end)

-- UI
re.on_draw_ui(function()
    if not imgui or not imgui.tree_node(MOD_NAME) then return end
    local changed = false
    local c, v

    c, v = imgui.checkbox("Enable", cfg.enabled)
    if c then cfg.enabled = v; changed = true; if not v then reset_speed() end end

    imgui.spacing()
    local presets = { 1.0, 1.1, 1.2, 1.3, 1.5, 2.0, 3.0 }
    for i, p in ipairs(presets) do
        if i > 1 then imgui.same_line() end
        local label = p == 1.0 and "Default" or string.format("x%.1f", p)
        if imgui.button(label) then
            for _, ch in ipairs(CHARACTERS) do
                cfg[ch.key].walk_speed = p
                cfg[ch.key].run_speed = p
            end
            changed = true
        end
    end
    imgui.spacing()

    local PLAYER_ACCENT = 0xFFBB8844
    imgui.push_style_color(7,  0xFF3E3330)
    imgui.push_style_color(8,  0xFF55443D)
    imgui.push_style_color(9,  0xFF665046)
    imgui.push_style_color(19, PLAYER_ACCENT)
    imgui.push_style_color(20, 0xFFDD9955)

    for idx, ch in ipairs(CHARACTERS) do
        if idx > 1 then imgui.separator() end
        imgui.text_colored("-- " .. ch.label .. " --", PLAYER_ACCENT)
        c, v = imgui.slider_float("Walk Speed##" .. ch.key, cfg[ch.key].walk_speed, 0.5, 3.0, "%.2f")
        if c then cfg[ch.key].walk_speed = v; changed = true end
        c, v = imgui.slider_float("Run Speed##" .. ch.key, cfg[ch.key].run_speed, 0.5, 3.0, "%.2f")
        if c then cfg[ch.key].run_speed = v; changed = true end
    end

    imgui.pop_style_color(5)

    imgui.spacing()
    if imgui.tree_node("Enemies") then
        c, v = imgui.checkbox("Enable##enemies", cfg.enemy_enabled)
        if c then cfg.enemy_enabled = v; changed = true; if not v then reset_enemy_speeds() end end

        imgui.spacing()

        local ENEMY_ACCENT = 0xFF444488
        imgui.push_style_color(7,  0xFF30303E)
        imgui.push_style_color(8,  0xFF3D3D55)
        imgui.push_style_color(9,  0xFF464666)
        imgui.push_style_color(19, ENEMY_ACCENT)
        imgui.push_style_color(20, 0xFF555599)

        local enemy_presets = { 1.0, 1.1, 1.2, 1.3, 1.5, 2.0, 3.0 }
        for i, p in ipairs(enemy_presets) do
            if i > 1 then imgui.same_line() end
            local label = (p == 1.0 and "Default" or string.format("x%.1f", p)) .. "##enemy_preset"
            if imgui.button(label) then
                cfg.enemies.walk_speed = p; cfg.enemies.run_speed = p
                cfg.the_girl.walk_speed = p; cfg.the_girl.run_speed = p
                changed = true
            end
        end
        imgui.spacing()

        imgui.text_colored("-- All Enemies --", ENEMY_ACCENT)
        c, v = imgui.slider_float("Walk Speed##enemies", cfg.enemies.walk_speed, 0.1, 5.0, "%.2f")
        if c then cfg.enemies.walk_speed = v; changed = true end
        c, v = imgui.slider_float("Run Speed##enemies", cfg.enemies.run_speed, 0.1, 5.0, "%.2f")
        if c then cfg.enemies.run_speed = v; changed = true end

        imgui.separator()

        imgui.text_colored("-- The Girl --", ENEMY_ACCENT)
        c, v = imgui.slider_float("Walk Speed##the_girl", cfg.the_girl.walk_speed, 0.1, 5.0, "%.2f")
        if c then cfg.the_girl.walk_speed = v; changed = true end
        c, v = imgui.slider_float("Run Speed##the_girl", cfg.the_girl.run_speed, 0.1, 5.0, "%.2f")
        if c then cfg.the_girl.run_speed = v; changed = true end

        imgui.pop_style_color(5)
        imgui.tree_pop()
    end

    if changed then save_config() end
    imgui.tree_pop()
end)

re.on_script_reset(function()
    reset_speed()
    reset_enemy_speeds()
end)
re.on_config_save(save_config)
