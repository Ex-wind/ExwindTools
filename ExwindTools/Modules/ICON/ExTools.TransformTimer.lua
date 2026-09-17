-- 噬灭变身计时纯业务模块；显示链唯一由通用中央 IconCollection 管理。
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local LSM = LibStub("LibSharedMedia-3.0", true)
local C_DurationUtil, Enum = _G.C_DurationUtil, _G.Enum
local MODULE_KEY = "ExTools.TransformTimer"
local DEMON_HUNTER_CLASS_ID, DEVOURER_SPEC_ID = 12, 1480
local TRANSFORM_AURA_SPELL_ID, TRACKED_CAST_SPELL_ID = 1217607, 1221150
local OUT_OF_COMBAT_ICON_ID, SOUND_ALERT_COUNT = 1305156, 5
local RefreshActiveSurfaces

-- 模块声明所有预设及全部 GUI 固定坐标；中央仅消费该声明。
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 2,
    features = { cooldown = true, timeText = true, stacksText = true },
    textSlots = { time = L["倒数文本"], stacks = L["层数文本（次数）"] },
    anchor = {
        dbPath = "icon",
        xKey = "x",
        yKey = "y",
        defaultX = 0,
        defaultY = 160,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 46,
        initialHeight = 46,
        clampedToScreen = true,
        -- GUI 位于 icon 作用域；直接绑定该表，不能再额外创建 icon.anchor。
        bindRoot = true,
    },
    preview = {
        positionGuiKeys = { "font_time", "font_stacks" },
        elements = {
            ["core.time"] = {
                guiKey = "font_time",
                movable = true,
                textRole = "time",
                tooltip = L["倒数文本"],
                position = { x = "font_time.x", y = "font_time.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
            ["icon.stacks"] = {
                guiKey = "font_stacks",
                movable = true,
                textRole = "stacks",
                tooltip = L["层数文本（次数）"],
                position = { x = "font_stacks.x", y = "font_stacks.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["变身图标"] },
        },
        sample = { icon = 7135881, stacks = "3", remaining = 12.3, duration = 30 },
    },
    defaults = {
        font_stacks = {
            a = 1,
            autoWidth = false,
            b = 1,
            enabled = true,
            fixedWidth = 200,
            font = "默认",
            g = 1,
            gradientEnabled = false,
            gradientLength = 0,
            gradientStart = 0,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            maxWidth = 0,
            outline = "OUTLINE",
            r = 1,
            rotation = 0,
            shadow = false,
            shadowColorA = 1,
            shadowColorB = 0,
            shadowColorG = 0,
            shadowColorR = 0,
            shadowX = 1,
            shadowY = -1,
            size = 24,
            x = 78.370567089843,
            y = 37.585764055216,
        },
        font_time = {
            a = 1,
            autoWidth = false,
            b = 0,
            enabled = true,
            fixedWidth = 200,
            font = "默认",
            g = 0.82,
            gradientEnabled = false,
            gradientLength = 0,
            gradientStart = 0,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            maxWidth = 0,
            outline = "OUTLINE",
            r = 1,
            rotation = 0,
            shadow = false,
            shadowColorA = 1,
            shadowColorB = 0,
            shadowColorG = 0,
            shadowColorR = 0,
            shadowX = 1,
            shadowY = -1,
            size = 24,
            x = 0.79990800147243,
            y = -31.988017688206,
        },
        icon = {
            alpha = 1,
            attachToCustom = false,
            blendMode = "BLEND",
            borderColorA = 1,
            borderColorB = 0,
            borderColorG = 0,
            borderColorR = 0,
            borderPadding = 0.6,
            borderSize = 0,
            borderTexture = "EX_Default",
            colorA = 1,
            colorB = 1,
            colorG = 1,
            colorR = 1,
            cooldown = {
                edgeAlpha = 0.75,
                showBling = false,
                showEdge = true,
                showSwipe = true,
                swipeAlpha = 0.55000001192093,
            },
            cropBottom = 0.92,
            cropLeft = 0.08,
            cropRight = 0.92,
            cropTop = 0.08,
            customAttachTarget = "",
            desaturated = false,
            enableCrop = true,
            height = 45,
            iconID = 7135881,
            reverse = false,
            rotation = 0,
            showBorder = true,
            showCooldown = true,
            showIcon = true,
            width = 45,
            x = 6,
            y = 189,
        },
        root = {
            inactiveIconMode = "褪色",
            layout = {
                direction = "RIGHT",
                maxVisible = 1,
                spacing = 0,
            },
            onlyShowOutOfCombatTransform = false,
            showCountText = true,
            soundAlert1Enabled = false,
            soundAlert1Second = "",
            soundAlert1Sound = "None",
            soundAlert2Enabled = false,
            soundAlert2Second = "",
            soundAlert2Sound = "None",
            soundAlert3Enabled = false,
            soundAlert3Second = "",
            soundAlert3Sound = "None",
            soundAlert4Enabled = false,
            soundAlert4Second = "",
            soundAlert4Sound = "None",
            soundAlert5Enabled = false,
            soundAlert5Second = "",
            soundAlert5Sound = "None",
            useOutOfCombatIcon = false,
        },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及刷新回调均属绑定或业务合同，禁止修改；复合控件必须整体引用，header 本身不等于卡片容器。
    gui = {
        version = 1,
        cards = {
            {
                id = "anchor", title = L["锚点设置"], collapsible = true,
                placement = { target = "sound_alerts", side = "below" },
                content = { kind = "composite", component = "anchorgroup", key = "anchor", parentKey = "icon" },
                settingsList = {
                    preserveHeader = true,
                    rows = {
                        { key = "anchor", fullWidth = true },
                    },
                },
            },
            {
                id = "icon", title = L["变身图标"], collapsible = true,
                placement = { target = "anchor", side = "below" },
                content = { kind = "composite", component = "icongroup", key = "icon" },
                settingsList = {
                    preserveHeader = true,
                    rows = {
                        { key = "icon", fullWidth = true },
                    },
                },
            },
            {
                id = "font_time", title = L["倒数文本"], collapsible = true,
                placement = { target = "icon", side = "below" },
                content = { kind = "composite", component = "fontgroup", key = "font_time" },
                settingsList = {
                    preserveHeader = true,
                    rows = {
                        { key = "font_time", fullWidth = true },
                    },
                },
            },
            {
                id = "font_stacks", title = L["层数文本（次数）"], collapsible = true,
                placement = { target = "font_time", side = "below" },
                content = { kind = "composite", component = "fontgroup", key = "font_stacks" },
                settingsList = {
                    preserveHeader = true,
                    rows = {
                        { key = "font_stacks", fullWidth = true },
                    },
                },
            },
            {
                id = "sound_alerts", title = L["声音提示"], collapsible = true,
                content = { kind = "grid", items = {
                    { h = 6, key = "soundAlert1Enabled", label = L["启用1"], type = "checkbox", w = 46, x = 1, y = 1 },
                    { h = 6, key = "soundAlert1Second", label = L["秒数"], labelPos = "top", type = "input", w = 46, x = 51, y = 1 },
                    { h = 6, key = "soundAlert1Sound", label = L["音效"], labelPos = "top", type = "lsm_sound", w = 46, x = 101, y = 1 },
                    { h = 6, key = "soundAlert2Enabled", label = L["启用2"], type = "checkbox", w = 46, x = 1, y = 15 },
                    { h = 6, key = "soundAlert2Second", label = L["秒数"], labelPos = "top", type = "input", w = 46, x = 51, y = 15 },
                    { h = 6, key = "soundAlert2Sound", label = L["音效"], labelPos = "top", type = "lsm_sound", w = 46, x = 101, y = 15 },
                    { h = 6, key = "soundAlert3Enabled", label = L["启用3"], type = "checkbox", w = 46, x = 1, y = 29 },
                    { h = 6, key = "soundAlert3Second", label = L["秒数"], labelPos = "top", type = "input", w = 46, x = 51, y = 29 },
                    { h = 6, key = "soundAlert3Sound", label = L["音效"], labelPos = "top", type = "lsm_sound", w = 46, x = 101, y = 29 },
                    { h = 6, key = "soundAlert4Enabled", label = L["启用4"], type = "checkbox", w = 46, x = 1, y = 43 },
                    { h = 6, key = "soundAlert4Second", label = L["秒数"], labelPos = "top", type = "input", w = 46, x = 51, y = 43 },
                    { h = 6, key = "soundAlert4Sound", label = L["音效"], labelPos = "top", type = "lsm_sound", w = 46, x = 101, y = 43 },
                    { h = 6, key = "soundAlert5Enabled", label = L["启用5"], type = "checkbox", w = 46, x = 1, y = 57 },
                    { h = 6, key = "soundAlert5Second", label = L["秒数"], labelPos = "top", type = "input", w = 46, x = 51, y = 57 },
                    { h = 6, key = "soundAlert5Sound", label = L["音效"], labelPos = "top", type = "lsm_sound", w = 46, x = 101, y = 57 },
                } },
                settingsList = {
                    preserveHeader = true,
                    columns = {
                        { title = L["启用"], width = 64 },
                        { title = L["秒数"], width = 120 },
                        { title = L["音效"], weight = 1.6 },
                    },
                    rows = {
                        { cells = {
                            { key = "soundAlert1Enabled", presentation = "switch" },
                            { key = "soundAlert1Second" },
                            { key = "soundAlert1Sound" },
                        } },
                        { cells = {
                            { key = "soundAlert2Enabled", presentation = "switch" },
                            { key = "soundAlert2Second" },
                            { key = "soundAlert2Sound" },
                        } },
                        { cells = {
                            { key = "soundAlert3Enabled", presentation = "switch" },
                            { key = "soundAlert3Second" },
                            { key = "soundAlert3Sound" },
                        } },
                        { cells = {
                            { key = "soundAlert4Enabled", presentation = "switch" },
                            { key = "soundAlert4Second" },
                            { key = "soundAlert4Sound" },
                        } },
                        { cells = {
                            { key = "soundAlert5Enabled", presentation = "switch" },
                            { key = "soundAlert5Second" },
                            { key = "soundAlert5Sound" },
                        } },
                    },
                },
            },
        },
    },
    samples = { icon = 7135881, stacks = "3", cooldownSeconds = 12.3, cooldownDuration = 30 },
}
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end
local transformActive, hasTimerValue, castCount = false, false, 0
local runtimeDuration, runtimeDurationStartTime, runtimeDurationClock = nil, 0, nil
local soundTriggered, soundAlertGeneration = {}, 0
local function IsEligible()
    local state = ExwindTools.State or {}; return state.ClassID == DEMON_HUNTER_CLASS_ID and
    state.SpecID == DEVOURER_SPEC_ID
end
local function ResetSoundAlerts()
    soundAlertGeneration = soundAlertGeneration + 1; for i = 1, SOUND_ALERT_COUNT do soundTriggered[i] = false end
end
local function PlaySoundAlert(index)
    local key = DB["soundAlert" .. index .. "Sound"]
    if LSM and type(key) == "string" and key ~= "" and key ~= "None" then
        local sound = LSM:Fetch("sound", key); if sound then PlaySoundFile(sound, "Master") end
    end
end
local function ScheduleSoundAlerts()
    local generation = soundAlertGeneration
    for i = 1, SOUND_ALERT_COUNT do
        local second = tonumber(DB["soundAlert" .. i .. "Second"]); if DB["soundAlert" .. i .. "Enabled"] == true and second and second > 0 then
            local index = i; C_Timer.After(second,
                function() if transformActive and soundAlertGeneration == generation and not soundTriggered[index] then
                        soundTriggered[index] = true; PlaySoundAlert(index)
                    end end)
        end
    end
end
local function GetTimerIcon()
    local db, inCombat = DB, ExwindTools.State and ExwindTools.State.InCombat
    if db.useOutOfCombatIcon and inCombat ~= true then return OUT_OF_COMBAT_ICON_ID end
    return (db.icon and db.icon.iconID) or
    (_G.C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(TRANSFORM_AURA_SPELL_ID)) or 236171
end
local function ShouldShowRuntime()
    if not IsEligible() or not (transformActive or hasTimerValue) then return false end
    local db = DB; if db.onlyShowOutOfCombatTransform then return db.useOutOfCombatIcon and
        ExwindTools.State.InCombat ~= true and transformActive end
    return true
end

local function MakeTextBounds(style)
    return {
        width = 200,
        height = math.max(18, tonumber(style.size) or 18),
        anchor = { point = "CENTER", relativePoint = "CENTER", x = tonumber(style.x) or 0, y = tonumber(style.y) or 0 },
    }
end

-- 模块只提交标准 IconCollection presentation；中央不识别变身、次数或音效业务。
local function BuildEntry(itemID, icon, stacks, cooldown, isPreview)
    local db = DB
    local iconStyle = db.icon or {}
    local width = math.max(1, tonumber(iconStyle.width) or 46)
    local height = math.max(1, tonumber(iconStyle.height) or 46)
    return {
        itemID = itemID,
        presentation = {
            style = { icon = iconStyle, text = { countdown = db.font_time or {}, stacks = db.font_stacks or {} } },
            icon = { value = icon },
            label = "",
            stacks = stacks,
            cooldown = cooldown,
            desaturated = not isPreview and not transformActive and db.inactiveIconMode == "褪色" or false,
            bodySize = { width = width, height = height },
            declaredBounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 },
            semanticBounds = {
                ["core.time"] = MakeTextBounds(db.font_time or {}),
                ["icon.stacks"] = MakeTextBounds(db.font_stacks or {}),
            },
            interaction = isPreview and EXUI:BuildStandardPreviewInteraction("Icon", db, MODULE_SPEC.preview.elements) or
            nil,
        },
    }
end

local function RefreshPreview()
    local sample = MODULE_SPEC.preview.sample
    local entry = BuildEntry("transform:preview", sample.icon, sample.stacks, {
        static = true, remaining = sample.remaining, duration = sample.duration,
    }, true)
    central:SetPreview({ entry }, LAYOUT)
end

RefreshPreview()

local function PublishRuntime()
    if not ShouldShowRuntime() then
        central:Clear()
        return
    end
    local cooldown = runtimeDuration and {
        mode = "DURATION",
        duration = runtimeDuration,
        clearIfZero = true,
        durationTextProperty = Enum and Enum.DurationTextBindingProperty and
        Enum.DurationTextBindingProperty.ElapsedDuration or nil,
    } or nil
    local stacks = DB.showCountText == true and tostring(castCount) or nil
    central:SetRuntime({ BuildEntry("transform:runtime", GetTimerIcon(), stacks, cooldown, false) }, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        local sample = MODULE_SPEC.preview.sample
        controller.previewEntries[1].presentation = BuildEntry("transform:preview", sample.icon, sample.stacks, {
            static = true, remaining = sample.remaining, duration = sample.duration,
        }, true).presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and ShouldShowRuntime() then
        local cooldown = runtimeDuration and { mode = "DURATION", duration = runtimeDuration, clearIfZero = true,
            durationTextProperty = Enum and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.ElapsedDuration or nil } or nil
        local stacks = DB.showCountText == true and tostring(castCount) or nil
        controller.runtimeEntries[1].presentation = BuildEntry("transform:runtime", GetTimerIcon(), stacks, cooldown, false).presentation
    end
end
local function StopTimer()
    if runtimeDuration then
        runtimeDurationClock = C_DurationUtil.CreateManualClock(); runtimeDurationClock:SetTime(GetTime() -
        runtimeDurationStartTime); runtimeDuration:SetClock(runtimeDurationClock); runtimeDuration:SetTimeFromStart(0,
            86400, 1)
    end
    transformActive, hasTimerValue = false, true; ResetSoundAlerts(); PublishRuntime()
end
local function StartTimer()
    if not IsEligible() then return end
    runtimeDuration = C_DurationUtil.CreateDuration(); runtimeDurationStartTime, runtimeDurationClock = GetTime(), nil; runtimeDuration
        :SetTimeFromStart(runtimeDurationStartTime, 86400, 1)
    transformActive, hasTimerValue, castCount = true, true, 0; ResetSoundAlerts(); ScheduleSoundAlerts(); PublishRuntime()
end
local function SyncAura()
    if not IsEligible() then
        transformActive, hasTimerValue, runtimeDuration, runtimeDurationStartTime, runtimeDurationClock, castCount =
        false, false, nil, 0, nil, 0; ResetSoundAlerts(); PublishRuntime(); return
    end
    local aura = _G.C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and
    C_UnitAuras.GetPlayerAuraBySpellID(TRANSFORM_AURA_SPELL_ID)
    if aura then if not transformActive then StartTimer() else PublishRuntime() end elseif transformActive then StopTimer() else
        PublishRuntime() end
end
ExwindTools:WatchState("ClassID", MODULE_KEY, SyncAura); ExwindTools:WatchState("SpecID", MODULE_KEY, SyncAura); ExwindTools
    :WatchState("InCombat", MODULE_KEY, PublishRuntime)
ExwindTools:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", MODULE_KEY,
    function(_, unit, _, spellID) if unit == "player" and tonumber(spellID) == TRACKED_CAST_SPELL_ID and transformActive then
            castCount = castCount + 1; PublishRuntime()
        end end)
ExwindTools:RegisterEvent("UNIT_AURA", MODULE_KEY, function(_, unit) if unit == "player" then SyncAura() end end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY,
    function()
        castCount = 0; ResetSoundAlerts(); C_Timer.After(.2, SyncAura)
    end)
ExwindTools:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", MODULE_KEY,
    function(_, unit) if unit == "player" then SyncAura() end end)
ExwindTools:RegisterEvent("TRAIT_CONFIG_UPDATED", MODULE_KEY, SyncAura)
ExwindTools:ReportReady(MODULE_KEY)
