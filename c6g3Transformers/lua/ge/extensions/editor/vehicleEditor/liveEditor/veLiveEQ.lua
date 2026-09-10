-- veLiveEQ.lua
-- Vehicle Editor Live Extension: Live EQ & Amplifier Adjuster
-- Displays and controls all c6g3SoundSystem_EQs defined in JBeam.
-- Follows the same topology and registration pattern as veSpeakerTransformer.lua.
-- EQs are read live from c6g3SoundSystem every frame - no stale cache.

local M = {}

local im = ui_imgui

local wndName      = "Live EQ"
local mainWndFlags = bit.bor(im.WindowFlags_NoBringToFrontOnFocus)
M.menuEntry        = "Live EQ"

local windowOpen = im.BoolPtr(false)

-- ==========================================
-- Vehicle tracking (mirrors veSpeakerTransformer)
-- ==========================================

local vEditor = {}

local function getActiveVehId()
    if vEditor.vehicle then return vEditor.vehicle:getID() end
    if be then
        local v = be:getPlayerVehicle(0)
        if v then return v:getID() end
    end
    return nil
end

local function switchVehicle(veh)
    if type(veh) == 'number' then
        vEditor.vehicle = be and be:getObjectByID(veh) or nil
    else
        vEditor.vehicle = veh
    end
end

local function removeVehicle(id)
    -- nothing to cache, kept for parity with veSpeakerTransformer lifecycle
end

-- ==========================================
-- UI colour constants
-- ==========================================

local accentColor = im.ImVec4(0.26, 0.59, 0.98, 1.0)
local white       = im.ImVec4(1.0,  1.0,  1.0,  1.0)
local grey        = im.ImVec4(0.6,  0.6,  0.6,  1.0)
local dimGrey     = im.ImVec4(0.45, 0.45, 0.45, 1.0)

local function sectionDivider()
    im.Dummy(im.ImVec2(0, 4))
    im.Separator()
    im.Dummy(im.ImVec2(0, 2))
end

-- ==========================================
-- Main window render
-- ==========================================

local function onUpdate()
    if not windowOpen[0] then return end
    if not editor or not editor.isEditorActive or not editor.isEditorActive() then return end

    local vehId = getActiveVehId()

    im.SetNextWindowSize(im.ImVec2(460, 600), im.Cond_FirstUseEver)
    im.SetNextWindowSizeConstraints(im.ImVec2(340, 240), im.ImVec2(900, 1600))

    if im.Begin(wndName, windowOpen, mainWndFlags) then
        im.PushStyleVar2(im.StyleVar_ItemSpacing, im.ImVec2(6, 5))

        -- Header
        im.TextColored(accentColor, "Live EQ & Amplifier Control")
        im.SameLine()
        im.TextColored(grey, "(c6g3SoundSystem_EQs)")
        im.Separator()
        im.Dummy(im.ImVec2(0, 2))

        if not vehId then
            im.TextColored(grey, "No active vehicle.")
        elseif not extensions.c6g3SoundSystem then
            im.TextColored(grey, "c6g3SoundSystem extension not loaded.")
        else
            if im.Button("Reload JBeam EQs") then
                if extensions.c6g3SoundSystem.reloadEQsFromJBeam then
                    extensions.c6g3SoundSystem.reloadEQsFromJBeam(vehId)
                end
            end
            im.SameLine()
            im.TextColored(dimGrey, "Vehicle ID: " .. tostring(vehId))
            im.Separator()
            im.Dummy(im.ImVec2(0, 4))

            -- Always read live from the backend - never from a stale cache
            local eqs = extensions.c6g3SoundSystem.getEQs(vehId)
            if type(eqs) ~= 'table' then eqs = {} end

            if #eqs == 0 then
                im.Dummy(im.ImVec2(0, 10))
                im.TextColored(grey, "No c6g3SoundSystem_EQs found on this vehicle.")
                im.TextColored(dimGrey, "Add a c6g3SoundSystem_EQs section to your JBeam file,")
                im.TextColored(dimGrey, "then press Ctrl+Shift+R to reload the vehicle.")
            else
                for eqIdx, eq in ipairs(eqs) do
                    local channelStr = table.concat(eq.channels or {"all"}, ", ")

                    -- EQ block header
                    im.TextColored(accentColor, "[" .. tostring(eqIdx) .. "]")
                    im.SameLine()
                    im.TextColored(white, tostring(eq.name))
                    im.SameLine()
                    im.TextColored(grey, "  ch: " .. channelStr)
                    im.SameLine()
                    im.TextColored(dimGrey, "  range: " .. tostring(eq.minGain or -15) .. " / " .. tostring(eq.maxGain or 15) .. " dB")

                    im.Dummy(im.ImVec2(0, 2))

                    -- Preamp slider
                    local preampVal = im.FloatPtr(tonumber(eq.preampDb) or 0.0)
                    im.TextColored(white, "  Preamp")
                    im.SameLine(120)
                    im.PushItemWidth(-10)
                    if im.SliderFloat("##leq_preamp_" .. tostring(eq.name), preampVal,
                                      eq.minGain or -15, eq.maxGain or 15, "%.1f dB") then
                        eq.preampDb = preampVal[0]
                        if extensions.c6g3SoundSystem.setEQPreamp then
                            extensions.c6g3SoundSystem.setEQPreamp(vehId, eq.name, preampVal[0])
                        end
                    end
                    im.PopItemWidth()

                    -- Band sliders
                    if eq.frequencies and #eq.frequencies > 0 then
                        im.Dummy(im.ImVec2(0, 2))
                        for bIdx, freq in ipairs(eq.frequencies) do
                            local bandVal = im.FloatPtr((eq.gains and tonumber(eq.gains[bIdx])) or 0.0)
                            local qLabel  = (eq.qValues and eq.qValues[bIdx])
                                            and string.format("  Q:%.2f", eq.qValues[bIdx]) or ""
                            im.TextColored(white, "  " .. tostring(freq) .. " Hz" .. qLabel)
                            im.SameLine(120)
                            im.PushItemWidth(-10)
                            if im.SliderFloat("##leq_band_" .. tostring(eq.name) .. "_" .. tostring(bIdx),
                                              bandVal, eq.minGain or -15, eq.maxGain or 15, "%.1f dB") then
                                if eq.gains then eq.gains[bIdx] = bandVal[0] end
                                if extensions.c6g3SoundSystem.setEQBandGain then
                                    extensions.c6g3SoundSystem.setEQBandGain(vehId, eq.name, bIdx, bandVal[0])
                                end
                            end
                            im.PopItemWidth()
                        end
                    else
                        im.TextColored(dimGrey, "  [Amplifier / Preamp block - no frequency bands]")
                    end

                    sectionDivider()
                end
            end
        end

        im.PopStyleVar()
    end
    im.End()
end

-- ==========================================
-- Lifecycle hooks (mirrors veSpeakerTransformer)
-- ==========================================

local function onVehicleSwitched(oldVehicle, newVehicle, player)
    switchVehicle(newVehicle)
end

local function onVehicleSpawned(id)
    removeVehicle(id)
    switchVehicle(id)
end

local function open()
    windowOpen[0] = true
end

local function onSerialize()
    return { windowOpen = windowOpen[0] }
end

local function onDeserialized(data)
    if data then windowOpen[0] = data.windowOpen end
end

-- ==========================================
-- Exports
-- ==========================================

M.onUpdate          = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleSpawned  = onVehicleSpawned
M.open              = open
M.onSerialize       = onSerialize
M.onDeserialized    = onDeserialized

return M
