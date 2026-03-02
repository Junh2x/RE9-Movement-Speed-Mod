--[[
    Layer 0 Diagnostic Script for RE9
    Shows real-time layer 0 animation state info.
    Use this to identify locomotion vs finisher animations.

    1) Press Insert -> Script Generated UI -> [Layer0 Diag]
    2) Walk/run around -> note the values
    3) Do a finisher (axe kill) -> note which values change
--]]

local diag = {}
local layer_methods = {}
local layer_fields = {}
local methods_scanned = false
local info = {}
local frame_count = 0

-- ============================================================
-- Helpers
-- ============================================================
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

local function get_player_motion()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local ctx = safe_call(cm, "getPlayerContextRef")
    if not ctx then return nil end
    local go = safe_call(ctx, "get_GameObject")
    if not go then return nil end
    return safe_call(go, "getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
end

-- ============================================================
-- Scan type definitions (once)
-- ============================================================
local function scan_type(type_name)
    local td = sdk.find_type_definition(type_name)
    if not td then return {}, {} end
    local methods = {}
    local fields = {}
    for _, m in ipairs(td:get_methods()) do
        table.insert(methods, m:get_name())
    end
    for _, f in ipairs(td:get_fields()) do
        table.insert(fields, f:get_name())
    end
    table.sort(methods)
    table.sort(fields)
    return methods, fields
end

-- ============================================================
-- Collect layer 0 info every N frames
-- ============================================================
local function obj_to_string(val)
    if val == nil then return "nil" end
    if type(val) ~= "userdata" then return tostring(val) end
    local s = tostring(val)
    -- Try common name methods
    local name = safe_call(val, "get_Name") or safe_call(val, "getName") or safe_call(val, "ToString")
    if name and tostring(name) ~= "" then
        s = s .. "  ->  " .. tostring(name)
    end
    return s
end

local interesting_getters = {
    -- Speed / Timing
    "get_Speed", "get_Frame", "get_EndFrame", "get_Weight",
    "get_BlendRate", "get_InterpolationFrame", "get_BaseSpeed",
    -- Bank / Motion ID
    "get_MotionBankID", "get_MotionID", "get_BankID",
    "get_CurrentBankID", "get_CurrentMotionID",
    -- Tree / Node
    "get_TreeCurrentNode", "get_HighestWeightMotionNode",
    "get_TreeObject", "get_TreeNodeCount",
    "get_CurrentNodeName", "get_CurrentNodeID",
    -- State / Tag
    "get_Tag", "get_MotionTag", "get_Enabled",
    "get_MaskBits", "get_LayerType",
}

local function collect_info()
    local lines = {}
    local motion = get_player_motion()
    if not motion then
        return { "Player motion: NOT FOUND" }
    end

    local layer = safe_call(motion, "getLayer", 0)
    if not layer then
        return { "Layer 0: NOT FOUND" }
    end

    -- Scan methods once
    if not methods_scanned then
        layer_methods, layer_fields = scan_type("via.motion.Layer")
        methods_scanned = true
    end

    -- Try interesting getters
    table.insert(lines, "[Layer 0 Properties]")
    for _, m in ipairs(interesting_getters) do
        local val = safe_call(layer, m)
        if val ~= nil then
            table.insert(lines, string.format("  %s = %s", m, obj_to_string(val)))
        end
    end

    -- Also try all scanned methods that start with "get" and take 0 params
    table.insert(lines, "")
    table.insert(lines, "[All Working Getters]")
    local seen = {}
    for _, m in ipairs(interesting_getters) do seen[m] = true end

    for _, m in ipairs(layer_methods) do
        if not seen[m] and (m:find("^get") or m:find("^Get")) then
            local val = safe_call(layer, m)
            if val ~= nil then
                table.insert(lines, string.format("  %s = %s", m, obj_to_string(val)))
            end
        end
    end

    -- Try tree node deep inspection
    local tree_node = safe_call(layer, "get_TreeCurrentNode")
                   or safe_call(layer, "getTreeCurrentNode")
    if tree_node then
        table.insert(lines, "")
        table.insert(lines, "[Tree Current Node]")
        local node_td_name = nil
        local ok2, td2 = pcall(function() return tree_node:get_type_definition() end)
        if ok2 and td2 then
            node_td_name = td2:get_full_name()
            table.insert(lines, "  TypeDef: " .. node_td_name)
            -- Try all getters on node
            for _, nm in ipairs(td2:get_methods()) do
                local mname = nm:get_name()
                if (mname:find("^get") or mname:find("^Get"))
                   and nm:get_num_params() == 0 then
                    local nval = safe_call(tree_node, mname)
                    if nval ~= nil then
                        table.insert(lines, string.format("  %s = %s", mname, obj_to_string(nval)))
                    end
                end
            end
        end
    end

    -- Also check the highest weight motion node
    local hw_node = safe_call(layer, "get_HighestWeightMotionNode")
                 or safe_call(layer, "getHighestWeightMotionNode")
    if hw_node and hw_node ~= tree_node then
        table.insert(lines, "")
        table.insert(lines, "[Highest Weight Node]")
        local ok3, td3 = pcall(function() return hw_node:get_type_definition() end)
        if ok3 and td3 then
            table.insert(lines, "  TypeDef: " .. td3:get_full_name())
            for _, nm in ipairs(td3:get_methods()) do
                local mname = nm:get_name()
                if (mname:find("^get") or mname:find("^Get"))
                   and nm:get_num_params() == 0 then
                    local nval = safe_call(hw_node, mname)
                    if nval ~= nil then
                        table.insert(lines, string.format("  %s = %s", mname, obj_to_string(nval)))
                    end
                end
            end
        end
    end

    -- Motion component level
    table.insert(lines, "")
    table.insert(lines, "[Motion Component]")
    local play_speed = safe_call(motion, "get_PlaySpeed")
    if play_speed then table.insert(lines, "  PlaySpeed = " .. tostring(play_speed)) end
    local lcount = safe_call(motion, "getLayerCount") or safe_call(motion, "get_LayerCount")
    if lcount then table.insert(lines, "  LayerCount = " .. tostring(lcount)) end

    return lines
end

-- ============================================================
-- Method list dump (shown once in UI)
-- ============================================================
local method_list_text = nil
local function get_method_list()
    if method_list_text then return method_list_text end
    if not methods_scanned then return "Not scanned yet..." end
    local parts = { "via.motion.Layer methods (" .. #layer_methods .. "):" }
    for _, m in ipairs(layer_methods) do
        table.insert(parts, "  " .. m)
    end
    if #layer_fields > 0 then
        table.insert(parts, "")
        table.insert(parts, "via.motion.Layer fields (" .. #layer_fields .. "):")
        for _, f in ipairs(layer_fields) do
            table.insert(parts, "  " .. f)
        end
    end
    method_list_text = table.concat(parts, "\n")
    return method_list_text
end

-- ============================================================
-- Update loop
-- ============================================================
re.on_pre_application_entry("LateUpdateBehavior", function()
    frame_count = frame_count + 1
    if frame_count % 15 == 0 then  -- ~4 times/sec at 60fps
        local ok, result = pcall(collect_info)
        if ok then
            info = result
        else
            info = { "ERROR: " .. tostring(result) }
        end
    end
end)

-- ============================================================
-- On-screen overlay (visible during gameplay)
-- ============================================================
re.on_frame(function()
    if not imgui then return end
    imgui.begin_window("Layer0 Diag", true, 0)
    for _, line in ipairs(info) do
        imgui.text(line)
    end
    imgui.end_window()
end)

-- ============================================================
-- REFramework menu (full details + method list)
-- ============================================================
local show_methods = false
re.on_draw_ui(function()
    if not imgui.tree_node("[Layer0 Diag]") then return end

    imgui.text("== Real-time Layer 0 Info ==")
    imgui.separator()
    for _, line in ipairs(info) do
        imgui.text(line)
    end

    imgui.separator()
    local changed, val = imgui.checkbox("Show All Methods", show_methods)
    if changed then show_methods = val end
    if show_methods then
        imgui.text(get_method_list())
    end

    imgui.tree_pop()
end)
