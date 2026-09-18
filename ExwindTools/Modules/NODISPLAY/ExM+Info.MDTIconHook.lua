-- [[ MDT 法术图标替换 ]]
-- { Key = "ExM+Info.MDTIconHook", Name = "MDT 法术图标替换", Desc = "将 MDT 地图中怪物头像替换为法术图标，并支持自动团队标记。", Category = 2 },

local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExM+Info.MDTIconHook"
local CUSTOM_ICONS_RENDERER = EXWIND_MODULE_KEY .. ".CustomIcons"
local BLACKLIST_RENDERER = EXWIND_MODULE_KEY .. ".Blacklist"
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXWIND_DEFAULTS = {
    enabled = true,
    useSpellIconMode = false,


    interruptMarkerIcon = "1", -- 默认骷髅
    eliteMarkerIcon = "8",     -- 默认星星

    customNPCIcons = {},
    blacklistNPCs = {},
    customIconsText = "", -- 缓存文本
    blacklistText = "",   -- 缓存文本
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)
EX_DB.customNPCIcons = EX_DB.customNPCIcons or {}
EX_DB.blacklistNPCs = EX_DB.blacklistNPCs or {}

local RAID_MARKER_DROPDOWN_ITEMS = {
    { value = "0", label = "无" },
    { value = "1", label = "星星 (1)" },
    { value = "2", label = "圆圈 (2)" },
    { value = "3", label = "菱形 (3)" },
    { value = "4", label = "三角 (4)" },
    { value = "5", label = "月亮 (5)" },
    { value = "6", label = "方块 (6)" },
    { value = "7", label = "叉叉 (7)" },
    { value = "8", label = "骷髅 (8)" },
}

local MDT_HOOK_INSTALLED = false
local MDT_BUTTONS_CREATED = false
local MDT_BUTTON_RETRY_PENDING = false
local MDT_PANEL_FRAME_HOOKED = false
local ELITE_LEVEL_BASE_CACHE = {}

local function RefreshMDTMap(silent)
    local MDT = _G.MDT
    local frame = MDT and MDT.main_frame
    if MDT and MDT.UpdateMap and frame and frame.sidePanel and frame.sidePanel.DifficultySlider then
        MDT:UpdateMap()
        if not silent then
            print("|cff00ff00[ExwindTools]|r " .. L["MDT 已刷新。"])
        end
    end
end

local function RefreshMDTMapDeferred(silent)
    local MDT = _G.MDT
    local frame = MDT and MDT.main_frame
    if MDT and MDT.Async and frame and frame.sidePanel and frame.sidePanel.DifficultySlider then
        MDT:Async(function()
            RefreshMDTMap(silent)
        end, "ExwindTools_MDTIconHook_RefreshMap", true)
        return
    end

    C_Timer.After(0, function()
        RefreshMDTMap(silent)
    end)
end

local function NormalizeMarkerIndex(value)
    local n = tonumber(value)
    if not n or n < 1 or n > 8 then
        return nil
    end
    return n
end

local function HasInterruptibleSpell(data)
    if not data or not data.spells then return false end
    for _, spellInfo in pairs(data.spells) do
        if type(spellInfo) == "table" and spellInfo.interruptible then
            return true
        end
    end
    return false
end

local function GetManualAssignment(enemyIdx, cloneIdx)
    local MDT = _G.MDT
    if not MDT or not MDT.GetCurrentPreset then return nil end
    local preset = MDT:GetCurrentPreset()
    local assignments = preset and preset.value and preset.value.enemyAssignments
    return assignments and assignments[enemyIdx] and assignments[enemyIdx][cloneIdx] or nil
end

local function GetCurrentDungeonEnemyTable()
    local MDT = _G.MDT
    if not MDT or not MDT.dungeonEnemies or not MDT.GetDB then return nil, nil end
    local db = MDT:GetDB()
    local dungeonIdx = db and db.currentDungeonIdx
    if not dungeonIdx then return nil, nil end
    return MDT.dungeonEnemies[dungeonIdx], dungeonIdx
end


local function GetEliteLevelBase()
    local enemies, dungeonIdx = GetCurrentDungeonEnemyTable()
    if not enemies or not dungeonIdx then return nil end

    local cached = ELITE_LEVEL_BASE_CACHE[dungeonIdx]
    if cached ~= nil then
        return cached or nil
    end

    local minLevel, maxLevel
    for _, enemy in pairs(enemies) do
        if enemy and not enemy.isBoss then
            local level = tonumber(enemy.level)
            if level then
                if not minLevel or level < minLevel then minLevel = level end
                if not maxLevel or level > maxLevel then maxLevel = level end
            end
        end
    end

    if not minLevel or not maxLevel or maxLevel <= minLevel then
        ELITE_LEVEL_BASE_CACHE[dungeonIdx] = false
        return nil
    end

    ELITE_LEVEL_BASE_CACHE[dungeonIdx] = minLevel
    return minLevel
end

local function IsEliteEnemy(data)
    if not data or data.isBoss then return false end
    local level = tonumber(data.level)
    if not level then return false end
    local baseLevel = GetEliteLevelBase()
    return baseLevel and level > baseLevel or false
end

local function ApplyCustomSettings()
    wipe(EX_DB.customNPCIcons)
    local rawMap = EX_DB.customIconsText or ""
    for line in rawMap:gmatch("[^\r\n]+") do
        local n, s = line:match("(%d+)%s*=%s*(%d+)")
        if n and s then
            EX_DB.customNPCIcons[tonumber(n)] = tonumber(s)
        end
    end

    wipe(EX_DB.blacklistNPCs)
    local rawBlack = EX_DB.blacklistText or ""
    for id in rawBlack:gmatch("(%d+)") do
        EX_DB.blacklistNPCs[tonumber(id)] = true
    end

    RefreshMDTMap(false)
end

local function GetRawTableColumns(kind)
    return {
        { title = kind == "custom" and L["NPC ID = 法术 ID"] or L["NPC ID"] },
        { title = L["操作"] },
    }
end

local function ReleaseRawTableControl(control)
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

local function TokenizeLines(raw)
    raw = type(raw) == "string" and raw or tostring(raw or "")
    if raw == "" then return {} end
    local lines, position = {}, 1
    while position <= #raw do
        local startPos = raw:find("[\r\n]", position)
        if not startPos then
            lines[#lines + 1] = { text = raw:sub(position), separator = "" }
            position = #raw + 1
        else
            local endPos = startPos
            if raw:sub(startPos, startPos) == "\r" and raw:sub(startPos + 1, startPos + 1) == "\n" then
                endPos = startPos + 1
            end
            lines[#lines + 1] = {
                text = raw:sub(position, startPos - 1),
                separator = raw:sub(startPos, endPos),
            }
            position = endPos + 1
            if position > #raw then
                lines[#lines + 1] = { text = "", separator = "" }
            end
        end
    end
    return lines
end

local function JoinLines(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        parts[#parts + 1] = line.text
        parts[#parts + 1] = line.separator
    end
    return table.concat(parts)
end

local function TokenizeBlacklist(raw)
    raw = type(raw) == "string" and raw or tostring(raw or "")
    local tokens, position = {}, 1
    while position <= #raw do
        local digit = raw:sub(position, position):match("%d") ~= nil
        local endPos = position + 1
        while endPos <= #raw and (raw:sub(endPos, endPos):match("%d") ~= nil) == digit do
            endPos = endPos + 1
        end
        tokens[#tokens + 1] = { text = raw:sub(position, endPos - 1), digit = digit }
        position = endPos
    end
    return tokens
end

local function JoinTokens(tokens)
    local parts = {}
    for _, token in ipairs(tokens) do parts[#parts + 1] = token.text end
    return table.concat(parts)
end

local function GetRawTableRecords(kind)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        local records = {}
        for index, line in ipairs(lines) do
            records[#records + 1] = {
                index = index,
                text = line.text,
                editable = true,
            }
        end
        return records
    end

    local tokens = TokenizeBlacklist(EX_DB.blacklistText)
    local records = {}
    for tokenIndex, token in ipairs(tokens) do
        local visibleText = token.text:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
        records[#records + 1] = {
            tokenIndex = tokenIndex,
            text = token.text,
            displayText = visibleText,
            editable = token.digit,
        }
    end
    return records
end

local function ReplaceRawRecord(kind, record, text)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        if not lines[record.index] then return false end
        lines[record.index].text = text
        EX_DB.customIconsText = JoinLines(lines)
    else
        if type(text) ~= "string" or not text:match("^%d+$") then return false end
        local tokens = TokenizeBlacklist(EX_DB.blacklistText)
        local token = tokens[record.tokenIndex]
        if not token or not token.digit then return false end
        token.text = text
        EX_DB.blacklistText = JoinTokens(tokens)
    end
    return true
end

local function DeleteRawRecord(kind, record)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        local line = lines[record.index]
        if not line then return false end
        if line.separator ~= "" then
            table.remove(lines, record.index)
        elseif record.index > 1 then
            lines[record.index - 1].separator = ""
            table.remove(lines, record.index)
        else
            table.remove(lines, record.index)
        end
        EX_DB.customIconsText = JoinLines(lines)
    else
        local tokens = TokenizeBlacklist(EX_DB.blacklistText)
        local token = tokens[record.tokenIndex]
        if not token or not token.digit then return false end
        table.remove(tokens, record.tokenIndex)
        EX_DB.blacklistText = JoinTokens(tokens)
    end
    return true
end

local function AppendRawRecord(kind, text)
    if kind == "custom" then
        local raw = type(EX_DB.customIconsText) == "string" and EX_DB.customIconsText
            or tostring(EX_DB.customIconsText or "")
        local separator = "\n"
        if raw == "" or raw:match("[\r\n]$") then separator = "" end
        EX_DB.customIconsText = raw .. separator .. text
    else
        if type(text) ~= "string" or not text:match("^%d+$") then return false end
        local raw = type(EX_DB.blacklistText) == "string" and EX_DB.blacklistText
            or tostring(EX_DB.blacklistText or "")
        EX_DB.blacklistText = raw .. (raw == "" and "" or ",") .. text
    end
    return true
end

local function ClearRawTableRows(controls)
    for index = #controls.rows, 1, -1 do
        local row = controls.rows[index]
        if row.inputIsEditBox then
            row.input:SetScript("OnEditFocusLost", nil)
            row.input:SetScript("OnEnterPressed", nil)
        end
        ReleaseRawTableControl(row.action)
        ReleaseRawTableControl(row.input)
        controls.rows[index] = nil
    end
end

local RebuildRawTable

local function QueueRawTableRebuild(host, ctx, kind)
    if host._exRawTableRefreshQueued then return end
    local lease = host._exRawTableLease
    host._exRawTableRefreshQueued = true
    C_Timer.After(0, function()
        if host._exRawTableLease ~= lease or not host._exRawTableControls then return end
        host._exRawTableRefreshQueued = nil
        RebuildRawTable(host, ctx, kind)
        ctx:RequestReflow()
    end)
end

RebuildRawTable = function(host, ctx, kind)
    local controls = host._exRawTableControls
    if not controls then return end
    ctx:ReleaseTablePresentation()
    ClearRawTableRows(controls)
    local records = GetRawTableRecords(kind)

    local addRow = {
        input = EXUI:CreateEditBox(host, "", 1, 28, nil, {
            placeholder = kind == "custom" and L["NPCID = SpellID"] or L["NPC ID"],
        }),
        inputIsEditBox = true,
    }
    addRow.action = EXUI:CreateButton(host, 1, 28, L["添加"], function()
        if AppendRawRecord(kind, addRow.input:GetText()) then
            RebuildRawTable(host, ctx, kind)
            ctx:RequestReflow()
        end
    end, { variant = "primary", compact = true })
    controls.rows[#controls.rows + 1] = addRow

    for _, record in ipairs(records) do
        local target = record
        local row = {}
        if record.editable then
            row.input = EXUI:CreateEditBox(host, record.text, 1, 28, nil, {})
            row.inputIsEditBox = true
            local committedText = record.text
            local function Commit(self)
                local text = self:GetText()
                if text == committedText then return end
                if ReplaceRawRecord(kind, target, text) then
                    committedText = text
                    QueueRawTableRebuild(host, ctx, kind)
                else
                    self:SetText(committedText)
                end
            end
            row.input:SetScript("OnEditFocusLost", function(self)
                if self._exSkipLostCommit then self._exSkipLostCommit = nil return end
                Commit(self)
            end)
            row.input:SetScript("OnEnterPressed", function(self)
                Commit(self)
                self._exSkipLostCommit = true
                self:ClearFocus()
            end)
            row.action = EXUI:CreateButton(host, 1, 28, L["删除"], function()
                if DeleteRawRecord(kind, target) then
                    RebuildRawTable(host, ctx, kind)
                    ctx:RequestReflow()
                end
            end, { variant = "danger", compact = true })
        else
            row.input = EXUI:CreateDescription(host, record.displayText, 1)
            row.action = EXUI:CreateDescription(host, "—", 1)
        end
        controls.rows[#controls.rows + 1] = row
    end

    local presentedRecords = {}
    for index = 2, #controls.rows do
        local row = controls.rows[index]
        presentedRecords[#presentedRecords + 1] = {
            cells = {
                { widget = row.input, type = row.inputIsEditBox and "input" or "text" },
                { widget = row.action, type = row.inputIsEditBox and "button" or "text" },
            },
        }
    end
    ctx:SetTableControls({
        add = {
            cells = {
                { widget = addRow.input, type = "input" },
                { widget = addRow.action, type = "button" },
            },
        },
        records = presentedRecords,
    })
end

local Grid = ExwindTools.Grid
if not Grid then error("MDTIconHook requires ExwindGrid", 2) end

local function RegisterRawTableControls(rendererKey, kind)
    Grid:RegisterTableControls(rendererKey, {
        mount = function(host, ctx)
            host._exRawTableLease = {}
            host._exRawTableControls = {
                rows = {},
            }
            RebuildRawTable(host, ctx, kind)
        end,
        update = function(host, ctx)
            RebuildRawTable(host, ctx, kind)
        end,
        release = function(host)
            local controls = host._exRawTableControls
            if controls then ClearRawTableRows(controls) end
            host._exRawTableControls = nil
            host._exRawTableRefreshQueued = nil
            host._exRawTableLease = nil
        end,
    })
end

RegisterRawTableControls(CUSTOM_ICONS_RENDERER, "custom")
RegisterRawTableControls(BLACKLIST_RENDERER, "blacklist")

local function EX_RegisterLayout()
    -- [声明迁移边界：设置页] 两组原始控件由唯一 shared table 承载，其余控件改为 typed sections。
    -- key/type、apply.func、NPC/法术解析与标记写入顺序均属业务合同，禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings", id = "common", title = L["通用设置"],
                items = {
                    { key = "enabled", type = "switch", label = L["开启功能"] },
                },
            },
            {
                kind = "table", id = "custom_icons", title = L["自定义图标"],
                key = "customIconsRecords", controlFactory = CUSTOM_ICONS_RENDERER,
                columns = GetRawTableColumns("custom"), supportsAdd = true,
            },
            {
                kind = "table", id = "blacklist", title = L["黑名单 NPC"],
                key = "blacklistRecords", controlFactory = BLACKLIST_RENDERER,
                columns = GetRawTableColumns("blacklist"), supportsAdd = true,
            },
            {
                kind = "settings", id = "apply", title = L["保存并刷新"],
                items = {
                    { key = "apply", type = "button", label = L["保存并刷新"], func = ApplyCustomSettings },
                },
            },
            {
                kind = "settings", id = "markers", title = L["标记设置"],
                items = {
                    { key = "interruptMarkerIcon", type = "select", label = L["打断标记"], options = RAID_MARKER_DROPDOWN_ITEMS },
                    { key = "btn_apply_interrupt_markers", type = "button", label = L["给所有打断怪标记"] },
                    { key = "eliteMarkerIcon", type = "select", label = L["精英标记"], options = RAID_MARKER_DROPDOWN_ITEMS },
                    { key = "btn_apply_elite_markers", type = "button", label = L["给所有精英怪标记"] },
                },
            },
        },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

local function ApplyTrueMarkersByRule(ruleType)
    local MDT = _G.MDT
    if not MDT or not MDT.GetCurrentPreset or not MDT.GetDB then
        print("|cffff8800[ExwindTools]|r " .. L["未检测到 MDT，无法写入真标记。"])
        return false
    end

    local preset = MDT:GetCurrentPreset()
    local db = MDT:GetDB()
    local dungeonIdx = db and db.currentDungeonIdx
    if not preset or not preset.value or not dungeonIdx then
        print("|cffff8800[ExwindTools]|r " .. L["未检测到 MDT 当前路线，无法写入真标记。"])
        return false
    end

    local enemies = MDT.dungeonEnemies and MDT.dungeonEnemies[dungeonIdx]
    if not enemies then
        print("|cffff8800[ExwindTools]|r " .. L["当前副本没有 MDT 敌人数据。"])
        return false
    end

    local markerIndex
    local matchFunc
    local ruleName
    if ruleType == "interrupt" then
        markerIndex = NormalizeMarkerIndex(EX_DB.interruptMarkerIcon)
        matchFunc = HasInterruptibleSpell
        ruleName = L["打断怪"]
    elseif ruleType == "elite" then
        markerIndex = NormalizeMarkerIndex(EX_DB.eliteMarkerIcon)
        matchFunc = IsEliteEnemy
        ruleName = L["精英怪"]
    else
        return false
    end

    if not markerIndex then
        print("|cffff8800[ExwindTools]|r " .. L["请先选择有效的团队标记。"])
        return false
    end

    preset.value.enemyAssignments = preset.value.enemyAssignments or {}
    local assignments = preset.value.enemyAssignments

    local appliedCount, skippedManualCount = 0, 0
    for enemyIdx, data in pairs(enemies) do
        if data and matchFunc(data) then
            for cloneIdx, _ in pairs(data.clones or {}) do
                local current = assignments[enemyIdx] and assignments[enemyIdx][cloneIdx] or nil
                if current == nil then
                    assignments[enemyIdx] = assignments[enemyIdx] or {}
                    assignments[enemyIdx][cloneIdx] = markerIndex
                    appliedCount = appliedCount + 1
                else
                    skippedManualCount = skippedManualCount + 1
                end
            end
        end
    end

    RefreshMDTMap(true)
    print(string.format("|cff00ff00[ExwindTools]|r " .. L["已给%s写入 MDT 真标记: 新增%d, 跳过已有标记%d"],
        ruleName, appliedCount, skippedManualCount))
    return true
end

local function ClearAllTrueMarkers()
    local MDT = _G.MDT
    if not MDT or not MDT.GetCurrentPreset then return false end
    local preset = MDT:GetCurrentPreset()
    if not preset or not preset.value then return false end

    preset.value.enemyAssignments = {}
    RefreshMDTMap(true)
    print("|cff00ff00[ExwindTools]|r " .. L["已清除当前 MDT 路线的所有标记。"])
    return true
end

local function InitializeMDTVisuals()
    if MDT_HOOK_INSTALLED then return true end

    local Mixin = _G.MDTDungeonEnemyMixin
    if not Mixin or not Mixin.SetUp then
        return false
    end

    MDT_HOOK_INSTALLED = true

    hooksecurefunc(Mixin, "SetUp", function(self, data, clone)
        if not EX_DB.enabled or not data then return end

        -- 功能1：头像替换为法术图标（原有逻辑）
        if EX_DB.useSpellIconMode and not data.isBoss and not data.iconTexture and not EX_DB.blacklistNPCs[data.id] then
            local targetID = EX_DB.customNPCIcons[data.id] or data.SPELLICON or (data.spells and next(data.spells))
            if targetID then
                local tex = C_Spell.GetSpellTexture(targetID)
                if tex and self.texture_Portrait then
                    self.texture_Portrait:SetTexture(tex)
                    self.texture_Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
    end)

    return true
end

-- [卡片迁移边界：外部UI] 下列视觉、位置、显隐、hook 与按钮 helper 均服务 MDT 自有窗口，不属于 ExwindTools 设置页；宿主锚点、按钮顺序、点击业务及显隐合同禁止修改。
local function UpdateMDTButtonsVisual()
    local toggleBtn = _G.ExMDT_Btn_ToggleIcon
    if toggleBtn and toggleBtn.Text then
        if EX_DB.useSpellIconMode then
            toggleBtn.Text:SetTextColor(0.2, 1, 0.2)   -- 绿色代表开启
        else
            toggleBtn.Text:SetTextColor(0.6, 0.6, 0.6) -- 灰色代表关闭
        end
    end
end

local function ApplyLoadedUIBackdrop(frame)
    if not frame or not ExwindTools:HasLoadedUIReplacement() then return false end
    local backdrop = frame._exLoadedUIBackdrop
    if not backdrop then
        backdrop = frame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(frame)
        frame._exLoadedUIBackdrop = backdrop
    end
    backdrop:SetColorTexture(0, 0, 0, 0.8)
    return true
end

local function UpdateMDTActionPanelPosition()
    local panel = _G.ExMDT_ActionPanel
    local MDT = _G.MDT
    local mainFrame = MDT and MDT.main_frame
    if not panel or not mainFrame then return end

    panel:ClearAllPoints()
    panel:SetPoint("TOP", mainFrame, "BOTTOM", 0, -10)
end

local function UpdateMDTActionPanelVisibility()
    local panel = _G.ExMDT_ActionPanel
    local MDT = _G.MDT
    local mainFrame = MDT and MDT.main_frame
    if not panel then return end

    if EX_DB.enabled and mainFrame and mainFrame:IsShown() then
        UpdateMDTActionPanelPosition()
        panel:Show()
    else
        panel:Hide()
    end
end

local function HookMDTMainFrame()
    if MDT_PANEL_FRAME_HOOKED then return end

    local MDT = _G.MDT
    local mainFrame = MDT and MDT.main_frame
    if not mainFrame then return end

    MDT_PANEL_FRAME_HOOKED = true
    mainFrame:HookScript("OnShow", function()
        C_Timer.After(0.05, UpdateMDTActionPanelVisibility)
    end)
    mainFrame:HookScript("OnHide", function()
        UpdateMDTActionPanelVisibility()
    end)
    mainFrame:HookScript("OnSizeChanged", function()
        UpdateMDTActionPanelPosition()
    end)
end

local function CreateMDTTextButton(name, parent, width, labelText, onClick)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(width, 22)
    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText(labelText)
    btn.Text = txt

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and ExwindTools.OpenConfig then
            ExwindTools:OpenConfig(EXWIND_MODULE_KEY)
        else
            onClick(self, button)
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if txt:GetTextColor() ~= 0.2 then
            txt:SetTextColor(1, 1, 1)
        end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(labelText .. " (" .. L["右键打开设置"] .. ")", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        UpdateMDTButtonsVisual()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return btn
end

-- [卡片迁移边界：自定义渲染] 下列按钮注入 MDT 自有窗口，不属于 ExwindTools 设置页；按钮顺序、外部锚点、点击业务和显隐 hook 禁止修改。
local function CreateMDTButtons()
    local MDT = _G.MDT
    if not MDT or not MDT.main_frame then
        if not MDT_BUTTON_RETRY_PENDING then
            MDT_BUTTON_RETRY_PENDING = true
            C_Timer.After(1, function()
                MDT_BUTTON_RETRY_PENDING = false
                CreateMDTButtons()
            end)
        end
        return false
    end

    if not _G.ExMDT_ActionPanel then
        local panel
        local hasLoadedUIReplacement = ExwindTools:HasLoadedUIReplacement()

        if hasLoadedUIReplacement then
            panel = CreateFrame("Frame", "ExMDT_ActionPanel", UIParent)
            panel:SetSize(300, 94)

            local title = panel:CreateFontString(nil, "OVERLAY")
            title:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
            title:SetPoint("TOP", 0, -8)
            title:SetTextColor(1, 0.82, 0)
            panel.TitleText = title

            local close = EXUI:CreatePicButton(panel, 24, 24,
                "Interface\\Buttons\\UI-Panel-CloseButton-Up",
                "Interface\\Buttons\\UI-Panel-CloseButton-Down",
                "Interface\\Buttons\\UI-Panel-CloseButton-Highlight",
                nil, true)
            close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
            panel.CloseButton = close

            ApplyLoadedUIBackdrop(panel)
        else
            panel = CreateFrame("Frame", "ExMDT_ActionPanel", UIParent, "DefaultPanelTemplate")
            panel:SetSize(300, 94)
        end

        panel:SetFrameStrata("MEDIUM")
        panel:SetToplevel(true)
        if panel.TitleText then
            panel.TitleText:SetText(L["MDT 快捷操作"])
        end

        if panel.CloseButton then
            panel.CloseButton:HookScript("OnClick", function()
                panel:Hide()
            end)
        end

        if _G.UISpecialFrames then
            local exists = false
            for _, frameName in ipairs(_G.UISpecialFrames) do
                if frameName == "ExMDT_ActionPanel" then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(_G.UISpecialFrames, "ExMDT_ActionPanel")
            end
        end

        local content = CreateFrame("Frame", nil, panel)
        content:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28)
        content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
        panel.Content = content

        local btnWidth = 132
        local btnHeight = 22

        local btnToggle = CreateMDTTextButton("ExMDT_Btn_ToggleIcon", content, btnWidth, L["替换图标"], function()
            EX_DB.useSpellIconMode = not EX_DB.useSpellIconMode
            RefreshMDTMap(true)
            UpdateMDTButtonsVisual()
        end)
        btnToggle:SetSize(btnWidth, btnHeight)
        btnToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

        local btnInt = CreateMDTTextButton("ExMDT_Btn_Int", content, btnWidth, L["标记打断"], function()
            ApplyTrueMarkersByRule("interrupt")
        end)
        btnInt:SetSize(btnWidth, btnHeight)
        btnInt:SetPoint("LEFT", btnToggle, "RIGHT", 8, 0)

        local btnElite = CreateMDTTextButton("ExMDT_Btn_Elite", content, btnWidth, L["标记精英"], function()
            ApplyTrueMarkersByRule("elite")
        end)
        btnElite:SetSize(btnWidth, btnHeight)
        btnElite:SetPoint("TOPLEFT", btnToggle, "BOTTOMLEFT", 0, -10)

        local btnClear = CreateMDTTextButton("ExMDT_Btn_Clear", content, btnWidth, L["清除标记"], function()
            ClearAllTrueMarkers()
        end)
        btnClear:SetSize(btnWidth, btnHeight)
        btnClear:SetPoint("LEFT", btnElite, "RIGHT", 8, 0)

        panel:Hide()
    end

    HookMDTMainFrame()
    UpdateMDTActionPanelPosition()
    MDT_BUTTONS_CREATED = true
    UpdateMDTButtonsVisual()
    UpdateMDTActionPanelVisibility()
    return true
end

local function TryBootstrapMDT()
    InitializeMDTVisuals()
    CreateMDTButtons()
    ELITE_LEVEL_BASE_CACHE = {}
end

TryBootstrapMDT()
C_Timer.After(0.1, TryBootstrapMDT)

ExwindTools:RegisterEvent("ADDON_LOADED", EXWIND_MODULE_KEY .. "_MDT", function(_, addonName)
    if addonName == "MythicDungeonTools" then
        C_Timer.After(0.2, function()
            ELITE_LEVEL_BASE_CACHE = {}
            TryBootstrapMDT()
        end)
    end
end)

local function RefreshActiveSurfaces()
    ELITE_LEVEL_BASE_CACHE = {}
    UpdateMDTButtonsVisual()
    UpdateMDTActionPanelVisibility()
    -- 一次性真标记方案：改配置不自动写入，避免干扰玩家在 MDT 里的手动操作。
    RefreshMDTMapDeferred(true)
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    if info.key == "btn_apply_interrupt_markers" then
        ApplyTrueMarkersByRule("interrupt")
    elseif info.key == "btn_apply_elite_markers" then
        ApplyTrueMarkersByRule("elite")
    end
    UpdateMDTButtonsVisual()
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
