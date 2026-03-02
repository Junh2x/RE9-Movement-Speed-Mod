--[[
    RE9 Character Diagnostic
    Dumps various player info to find Grace vs Leon distinguishing data.
    Press Insert -> Script Generated UI -> [Character Diag]
--]]

local MOD_NAME = "[Character Diag]"
local info_lines = {}
local frame_count = 0

local function safe_call(obj, method, ...)
    if not obj then return nil end
    local ok, ret = pcall(obj.call, obj, method, ...)
    if ok then return ret end
    return nil
end

local function safe_field(obj, name)
    if not obj then return nil end
    local ok, ret = pcall(obj.get_field, obj, name)
    if ok then return ret end
    return nil
end

local function get_type_full_name(obj)
    if obj == nil then return nil end
    local ok_td, td = pcall(obj.get_type_definition, obj)
    if not ok_td or td == nil then return nil end
    local ok_name, full_name = pcall(td.get_full_name, td)
    if ok_name and type(full_name) == "string" then return full_name end
    return nil
end

local function to_str(val)
    if val == nil then return "nil" end
    return tostring(val)
end

local function collect_info()
    local lines = {}

    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then
        return { "CharacterManager: NOT FOUND" }
    end

    local ctx = safe_call(cm, "getPlayerContextRef")
    if not ctx then
        return { "PlayerContext: NOT FOUND" }
    end

    -- Context type
    table.insert(lines, "Context Type: " .. (get_type_full_name(ctx) or "N/A"))

    -- GameObject name
    local go = safe_call(ctx, "get_GameObject")
    if go then
        local go_name = safe_call(go, "get_Name")
        table.insert(lines, "GameObject Name: " .. to_str(go_name))
    end

    -- Updater type
    local updater = safe_call(ctx, "get_Updater")
    table.insert(lines, "Updater Type: " .. (get_type_full_name(updater) or "N/A"))

    -- Try common character ID fields/methods on context
    local try_methods = {
        "get_CharacterID", "get_CharaID", "get_CharacterKind",
        "get_CharacterType", "get_PlayerNo", "get_PlayerIndex",
        "get_CharaType", "get_ID", "get_UniqueID",
        "getCharacterID", "getCharaID", "getPlayerNo",
    }
    table.insert(lines, "--- Context Methods ---")
    for _, m in ipairs(try_methods) do
        local val = safe_call(ctx, m)
        if val ~= nil then
            table.insert(lines, "  " .. m .. " = " .. to_str(val))
        end
    end

    -- Try common fields on context
    local try_fields = {
        "_CharacterID", "_CharaID", "_CharacterKind",
        "_CharacterType", "_PlayerNo", "_PlayerIndex",
        "_CharaType", "_ID", "_UniqueID",
        "<CharacterID>k__BackingField", "<CharaID>k__BackingField",
        "<PlayerNo>k__BackingField",
    }
    table.insert(lines, "--- Context Fields ---")
    for _, f in ipairs(try_fields) do
        local val = safe_field(ctx, f)
        if val ~= nil then
            table.insert(lines, "  " .. f .. " = " .. to_str(val))
        end
    end

    -- Try updater fields/methods
    if updater then
        local updater_methods = {
            "get_CharacterID", "get_CharaID", "get_CharacterKind",
            "get_CharacterType", "get_PlayerType", "get_ID",
        }
        table.insert(lines, "--- Updater Methods ---")
        for _, m in ipairs(updater_methods) do
            local val = safe_call(updater, m)
            if val ~= nil then
                table.insert(lines, "  " .. m .. " = " .. to_str(val))
            end
        end

        local updater_fields = {
            "_CharacterID", "_CharaID", "_CharacterKind",
            "_CharacterType", "_PlayerType", "_ID",
        }
        table.insert(lines, "--- Updater Fields ---")
        for _, f in ipairs(updater_fields) do
            local val = safe_field(updater, f)
            if val ~= nil then
                table.insert(lines, "  " .. f .. " = " .. to_str(val))
            end
        end
    end

    -- Try CharacterManager methods
    local cm_methods = {
        "get_PlayerCharacterKind", "get_CurrentPlayerCharacterID",
        "getPlayerCharacterKind", "getCurrentPlayerCharacterID",
        "get_PlayerType", "getPlayerType",
    }
    table.insert(lines, "--- CharacterManager Methods ---")
    for _, m in ipairs(cm_methods) do
        local val = safe_call(cm, m)
        if val ~= nil then
            table.insert(lines, "  " .. m .. " = " .. to_str(val))
        end
    end

    return lines
end

re.on_pre_application_entry("LateUpdateBehavior", function()
    frame_count = frame_count + 1
    if frame_count % 60 == 0 then
        local ok, result = pcall(collect_info)
        if ok then
            info_lines = result
        else
            info_lines = { "ERROR: " .. tostring(result) }
        end
    end
end)

re.on_frame(function()
    if not imgui then return end
    imgui.begin_window("Character Diag", true, 0)
    for _, line in ipairs(info_lines) do
        imgui.text(line)
    end
    imgui.end_window()
end)

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME) then return end
    for _, line in ipairs(info_lines) do
        imgui.text(line)
    end
    imgui.tree_pop()
end)
