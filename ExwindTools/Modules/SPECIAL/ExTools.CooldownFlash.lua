-- =============================================================
-- [[ 技能就绪闪现 ]]
-- 法术冷却结束时，在屏幕中央播放一次「图标放大 + 淡出」。
-- 冷却结束的判定来自原生 Cooldown 的 OnCooldownDone，只把冷却 Duration
-- 对象原样直传，不读取、比较或换算冷却数值。
-- 动画按官方 Blizzard_CooldownViewer/PandemicAlertAnimation.xml 的
-- CooldownPandemicFXTemplate 写法：同一 order 内 Scale 与 Alpha 并行。
-- 显示为一次性缩放淡出特效：Core 显示手册未覆盖该形态（IconCollection 与
-- MaterialCollection 只有静态 SetItemVisualEffects，Alpha 序列只在
-- TextCollection），已核实 Core 源码无既有封装，按《动画与发光》的原生
-- AnimationGroup 生命周期自行持有。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local Grid = ExwindTools.Grid
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Spell = _G.C_Spell
local GetTime = _G.GetTime
local MODULE_KEY = "ExTools.CooldownFlash"
local SPELL_LIST_RENDERER = MODULE_KEY .. ".SpellList"
local FALLBACK_ICON_FILE_ID = 134400
local MIN_REPLAY_INTERVAL = 0.5
local ICON_CROP = 0.08
local ApplyAppearance

ExwindTools:RegisterExternalModule({
    Key = MODULE_KEY,
    Name = L["技能就绪闪现"],
    Desc = L["法术冷却结束时，在屏幕中央放大淡出一次法术图标。"],
    Category = 6,
})

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
-- spells 是法术 ID 字符串数组，按声明合同在 root 中完整声明。
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, {
    root = {
        enabled = true,
        spells = {},
        size = 84,
        offsetX = 0,
        offsetY = 0,
        scaleFrom = 0.6,
        scaleTo = 2,
        duration = 0.8,
    },
})
local DB = ExwindTools:GetModuleDB(MODULE_KEY)

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic — 法术资料
-- =========================================================
local spellDisplayCache = {}

local function ParseSpellID(value)
    local spellID = tonumber(value)
    if not spellID or spellID <= 0 or spellID % 1 ~= 0 then
        return nil
    end
    return spellID
end

local function GetSpellList()
    if type(DB.spells) ~= "table" then return {} end
    return DB.spells
end

local function IsTrackedSpell(spellID)
    if not spellID then return false end
    for _, value in ipairs(GetSpellList()) do
        if ParseSpellID(value) == spellID then return true end
    end
    return false
end

-- 取得法术名称与图标；未缓存时按官方流程请求一次，不自行推断失败。
local function GetSpellRecord(value)
    local spellID = ParseSpellID(value)
    if not spellID then return nil end

    local cached = spellDisplayCache[spellID]
    if not cached then
        cached = {}
        spellDisplayCache[spellID] = cached
    end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info then
        cached.name = info.name
        cached.iconID = info.iconID
        cached.requested = nil
        cached.completed = true
    elseif C_Spell and C_Spell.RequestLoadSpellData and not cached.requested and not cached.completed then
        local exists = not C_Spell.DoesSpellExist or C_Spell.DoesSpellExist(spellID) == true
        local isCached = C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(spellID) == true
        if exists and not isCached then
            cached.requested = true
            C_Spell.RequestLoadSpellData(spellID)
        else
            cached.completed = true
        end
    end

    return cached
end

local function GetSpellDisplayText(value)
    if not ParseSpellID(value) then return L["无效法术 ID"] end
    local record = GetSpellRecord(value)
    local name = (record and record.name) or L["未知法术"]
    if record and record.iconID then
        return string.format("|T%s:20:20:0:0|t %s", tostring(record.iconID), name)
    end
    return name
end

-- 闪现与预览都用这里取图标；没有法术时由调用方决定占位。
local function ResolveIconFileID(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local fileID = C_Spell.GetSpellTexture(spellID)
        if fileID then return fileID end
    end
    return nil
end

local function GetFirstTrackedIconFileID()
    for _, value in ipairs(GetSpellList()) do
        local spellID = ParseSpellID(value)
        local fileID = spellID and ResolveIconFileID(spellID)
        if fileID then return fileID end
    end
    return nil
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — 法术列表表格
-- =========================================================
local spellListHost, spellListContext
local RebuildSpellList

local function ReleaseListControl(control)
    if not control then return end
    if EXUI.RestoreSettingsListControl then EXUI:RestoreSettingsListControl(control) end
    local factory = _G.ExwindFactory
    if factory and control._isCompositeHost then
        factory:ReleaseCompositeHost(control)
    elseif factory then
        factory:ReleaseGridWidget(control)
    else
        control:Hide()
        control:SetParent(nil)
    end
end

local function ClearSpellListRows(controls)
    for index = #controls.rows, 1, -1 do
        local record = controls.rows[index]
        if record.idControlIsEditBox then
            -- OnEditFocusLost 槽位上有 Core 的焦点画器，走 ClearControlScript
            -- 清槽位时一并丢掉安装记录，下一次借用才会重装画器。
            EXUI:ClearControlScript(record.idControl, "OnEditFocusLost")
            record.idControl:SetScript("OnEnterPressed", nil)
        end
        ReleaseListControl(record.action)
        ReleaseListControl(record.nameText)
        ReleaseListControl(record.idControl)
        controls.rows[index] = nil
    end
end

local SPELL_LIST_COLUMNS = {
    { title = L["法术 ID"] },
    { title = L["法术"] },
    { title = L["操作"] },
}

RebuildSpellList = function(host, ctx)
    local controls = host and host._exCooldownFlashList
    if not controls then return end
    ctx:ReleaseTablePresentation()
    ClearSpellListRows(controls)

    local entries = GetSpellList()

    local addRecord = {
        idControl = EXUI:CreateEditBox(host, "", 1, 28, nil, { placeholder = L["输入法术 ID"] }),
        idControlIsEditBox = true,
        nameText = EXUI:CreateDescription(host, L["填入法术 ID 后按添加或回车"], 1),
    }
    -- 添加按钮与输入框回车走同一条路径。
    local function AddFromInput()
        local spellID = ParseSpellID(addRecord.idControl:GetText())
        if not spellID then return end
        local list = GetSpellList()
        list[#list + 1] = tostring(spellID)
        addRecord.idControl:SetText("")
        RebuildSpellList(host, ctx)
        ctx:RequestReflow()
    end
    addRecord.idControl:SetScript("OnEnterPressed", function(self)
        -- 先交还焦点，再重建行；重建会释放这个输入框本身。
        self:ClearFocus()
        AddFromInput()
    end)
    addRecord.action = EXUI:CreateButton(host, 1, 28, L["添加"], AddFromInput,
        { variant = "primary", compact = true })
    controls.rows[#controls.rows + 1] = addRecord

    for index, value in ipairs(entries) do
        local rowIndex = index
        local record = {}
        record.idControl = EXUI:CreateDescription(host, tostring(value), 1)
        record.nameText = EXUI:CreateDescription(host, GetSpellDisplayText(value), 1)
        record.spellID = ParseSpellID(value)
        record.action = EXUI:CreateButton(host, 1, 28, L["删除"], function()
            local list = GetSpellList()
            table.remove(list, rowIndex)
            RebuildSpellList(host, ctx)
            ctx:RequestReflow()
        end, { variant = "danger", compact = true })
        controls.rows[#controls.rows + 1] = record
    end

    local presented = {}
    for index = 2, #controls.rows do
        local record = controls.rows[index]
        presented[#presented + 1] = {
            cells = {
                { widget = record.idControl, type = "text" },
                { widget = record.nameText, type = "text" },
                { widget = record.action, type = "button" },
            },
        }
    end

    ctx:SetTableControls({
        add = {
            cells = {
                { widget = addRecord.idControl, type = "input" },
                { widget = addRecord.nameText, type = "text" },
                { widget = addRecord.action, type = "button" },
            },
        },
        records = presented,
    })
end

if Grid and Grid.RegisterTableControls then
    Grid:RegisterTableControls(SPELL_LIST_RENDERER, {
        mount = function(host, ctx)
            spellListHost, spellListContext = host, ctx
            host._exCooldownFlashList = { rows = {} }
            RebuildSpellList(host, ctx)
        end,
        update = function(host, ctx)
            spellListHost, spellListContext = host, ctx
            RebuildSpellList(host, ctx)
        end,
        release = function(host)
            local controls = host._exCooldownFlashList
            if controls then ClearSpellListRows(controls) end
            host._exCooldownFlashList = nil
            if spellListHost == host then
                spellListHost, spellListContext = nil, nil
            end
        end,
    })
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — 页面声明
-- =========================================================
ExwindTools:RegisterModuleLayout(MODULE_KEY, {
    version = 1,
    sections = {
        {
            kind = "composite", id = "common", title = L["模块设置"],
            component = "modulecommonsettings", key = "moduleCommon",
            opts = {
                bindRoot = true,
                fields = { { path = "enabled", type = "checkbox", label = L["启用"] } },
            },
        },
        {
            kind = "table", id = "spells", title = L["监控法术"],
            description = L["列表中任一法术冷却结束时播放一次闪现。"],
            key = "spells", controlFactory = SPELL_LIST_RENDERER,
            columns = SPELL_LIST_COLUMNS, supportsAdd = true,
        },
        {
            kind = "settings", id = "test", title = L["测试"],
            items = {
                { key = "btn_test", type = "button", label = L["测试播放"] },
            },
        },
        {
            kind = "settings", id = "appearance", title = L["闪现外观"],
            items = {
                { key = "size", type = "slider", label = L["图标大小"], min = 32, max = 150, step = 2 },
                { key = "offsetX", type = "slider", label = L["水平偏移"], min = -800, max = 800, step = 1 },
                { key = "offsetY", type = "slider", label = L["垂直偏移"], min = -600, max = 600, step = 1 },
                { key = "scaleFrom", type = "slider", label = L["起始缩放"], min = 0.1, max = 3, step = 0.05 },
                { key = "scaleTo", type = "slider", label = L["结束缩放"], min = 0.1, max = 5, step = 0.05 },
                { key = "duration", type = "slider", label = L["动画时长"], min = 0.1, max = 3, step = 0.05 },
            },
        },
    },
})

-- 设置变更只重投影已经存在的宿主与动画参数；不在这里创建或播放。
EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = function()
        ApplyAppearance()
    end,
})

if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local lastPlayTime = 0
local displayHost, flashTexture, flashGroup, scaleAnim, alphaAnim

local function EnsureDisplay()
    if displayHost then return end

    displayHost = CreateFrame("Frame", nil, UIParent)
    displayHost:SetFrameStrata("HIGH")
    displayHost:EnableMouse(false)
    displayHost:Hide()

    flashTexture = EXUI:CreateVisualTexture(displayHost, _G.EXBASEFRAME)
    flashTexture:SetPoint("CENTER", displayHost, "CENTER", 0, 0)
    flashTexture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    flashGroup = flashTexture:CreateAnimationGroup()
    scaleAnim = flashGroup:CreateAnimation("Scale")
    scaleAnim:SetOrder(1)
    scaleAnim:SetOrigin("CENTER", 0, 0)
    scaleAnim:SetSmoothing("OUT")
    alphaAnim = flashGroup:CreateAnimation("Alpha")
    alphaAnim:SetOrder(1)
    alphaAnim:SetSmoothing("OUT")
    flashGroup:SetScript("OnFinished", function()
        displayHost:Hide()
    end)

    ApplyAppearance()
end

ApplyAppearance = function()
    if not displayHost then return end

    local size = math.max(8, tonumber(DB.size) or 84)
    local seconds = math.max(0.1, tonumber(DB.duration) or 0.8)
    local scaleFrom = math.max(0.01, tonumber(DB.scaleFrom) or 0.6)
    local scaleTo = math.max(0.01, tonumber(DB.scaleTo) or 2)

    displayHost:SetSize(size, size)
    displayHost:ClearAllPoints()
    displayHost:SetPoint("CENTER", UIParent, "CENTER", tonumber(DB.offsetX) or 0, tonumber(DB.offsetY) or 0)
    flashTexture:SetSize(size, size)

    scaleAnim:SetDuration(seconds)
    scaleAnim:SetScaleFrom(scaleFrom, scaleFrom)
    scaleAnim:SetScaleTo(scaleTo, scaleTo)
    alphaAnim:SetDuration(seconds)
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(0)
end

local function PlayFlash(spellID, force)
    if force ~= true and DB.enabled ~= true then return end

    local now = GetTime()
    if force ~= true and (now - lastPlayTime) < MIN_REPLAY_INTERVAL then return end
    lastPlayTime = now

    EnsureDisplay()
    flashGroup:Stop()
    ApplyAppearance()

    local fileID = ResolveIconFileID(spellID) or GetFirstTrackedIconFileID() or FALLBACK_ICON_FILE_ID
    flashTexture:SetTexture(fileID)
    flashTexture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    flashTexture:SetAlpha(1)
    displayHost:Show()
    flashGroup:Play()
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic — 冷却监听
-- =========================================================
-- 每个法术一个隐藏 Cooldown：冷却结束通知的唯一来源是原生 OnCooldownDone。
local watcherHost
local watchersBySpell = {}

local function EnsureWatcherHost()
    if watcherHost then return watcherHost end
    watcherHost = CreateFrame("Frame", nil, UIParent)
    watcherHost:SetSize(1, 1)
    watcherHost:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    watcherHost:EnableMouse(false)
    watcherHost:SetAlpha(0)
    watcherHost:Show()
    return watcherHost
end

local function EnsureWatcher(spellID)
    local watcher = watchersBySpell[spellID]
    if watcher then return watcher end

    watcher = CreateFrame("Cooldown", nil, EnsureWatcherHost(), "CooldownFrameTemplate")
    watcher:SetAllPoints(watcherHost)
    watcher:EnableMouse(false)
    watcher:SetDrawSwipe(false)
    watcher:SetDrawEdge(false)
    watcher:SetDrawBling(false)
    watcher:SetHideCountdownNumbers(true)
    watcher.noCooldownCount = true
    watcher.noOCC = true
    watcher:SetScript("OnCooldownDone", function()
        if IsTrackedSpell(spellID) then PlayFlash(spellID) end
    end)
    watchersBySpell[spellID] = watcher
    return watcher
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("SPELL_UPDATE_COOLDOWN", MODULE_KEY, function(_, spellID, baseSpellID)
    if DB.enabled ~= true then return end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return end

    local tracked = (IsTrackedSpell(spellID) and spellID)
        or (IsTrackedSpell(baseSpellID) and baseSpellID)
        or nil
    if not tracked then return end

    -- MayReturnNothing：整次可能没有返回；拿到的 Duration 只原样直传。
    local duration = C_Spell.GetSpellCooldownDuration(tracked, true)
    if not duration then return end

    local watcher = EnsureWatcher(tracked)
    watcher:SetCooldownFromDurationObject(duration, true)
    watcher:Show()
end)

-- Grid 只发布纯点击状态；测试播放不读取任何冷却数值。
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY, function(click)
    if click and click.key == "btn_test" then
        PlayFlash(nil, true)
    end
end)

-- 法术资料异步返回后补上列表里的名称与图标。
ExwindTools:RegisterEvent("SPELL_DATA_LOAD_RESULT", MODULE_KEY, function(_, spellID, success)
    spellID = tonumber(spellID)
    local cached = spellID and spellDisplayCache[spellID]
    if not cached then return end
    cached.requested = nil
    cached.completed = true
    if success == true and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            cached.name = info.name
            cached.iconID = info.iconID
        end
    end
    if spellListHost and spellListContext then
        RebuildSpellList(spellListHost, spellListContext)
    end
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
