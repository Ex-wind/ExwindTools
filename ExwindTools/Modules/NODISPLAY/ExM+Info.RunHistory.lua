-- [[ 大秘境赛季记录 ]]
-- { Key = "ExM+Info.RunHistory", Name = "大秘境赛季记录", Desc = "查看本赛季大秘境通关记录表格。", Category = 2 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+Info.RunHistory"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB

-- 3. 数据初始化
-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXMYRUN_DEFAULTS = {
    size = 16,
    outline = "OUTLINE",
    font = nil,
    filterThisWeek = false,
    filterTimed = false,
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = 0,
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXMYRUN_DEFAULTS)

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================


-- 2. 设置页（V2）
EXUI:RegisterModuleSettingsPageV2(EXWIND_MODULE_KEY, {
    version = 2,
    cards = {
        { id = "filters", kind = "card", title = L["过滤设置"], children = {
            { id = "filterThisWeek", kind = "control", controlType = "switch", path = "filterThisWeek",
                label = L["只看本周记录"] },
            { id = "filterTimed", kind = "control", controlType = "switch", path = "filterTimed",
                label = L["只看限时记录"] },
            { id = "size", kind = "control", controlType = "slider", path = "size",
                label = L["显示字号"], min = 10, max = 30 },
        } },
        { id = "preview", kind = "card", title = L["记录预览"], children = {
            { id = "open_row", kind = "setting", label = L["打开记录预览"],
                description = L["此模块提供了一个可随时调用的详细战绩表格。使用 /emr 打开窗口。"], children = {
                { id = "open", kind = "button", text = L["打开记录预览"], clickKey = "open" },
            } },
        } },
    },
})

-- 按钮监听
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(data)
    if data.key == "open" then
        if _G.EXMYRUN and _G.EXMYRUN.ToggleWindow then _G.EXMYRUN:ToggleWindow() end
    end
end)

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 核心业务逻辑
-- =========================================================
local EXMYRUN = {}
_G.EXMYRUN = EXMYRUN
-- (请勿在此处重复定义 EX_DB.WatchState，统一使用全局监听)

-- 5. 业务逻辑 (变量命名遵循规范)
-- local EXMYRUN = {} -- [Fix] 删除重复定义

EXMYRUN.TimeOffset = 8
EXMYRUN.FrameWidth = 960
EXMYRUN.FrameHeight = 620

EXMYRUN.MainFrame = nil
EXMYRUN.SortState = { key = "date", asc = false }
EXMYRUN.DisplayData = {}

-- 工具函数
local function EXMYRUN_FormatTime(seconds)
    if not seconds then return "00:00" end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function EXMYRUN_GetAdjustedCompletionDate(completionDate)
    if not completionDate then return nil end

    local year = completionDate.year
    local month = completionDate.month
    local monthDay = completionDate.monthDay or completionDate.day
    local hour = completionDate.hour or 0
    local minute = completionDate.minute or 0

    if not year or not month or not monthDay then
        return nil
    end

    if year < 100 then
        year = year + 2000
    end
    if month < 1 then
        month = month + 1
    end
    if monthDay < 1 then
        monthDay = monthDay + 1
    end

    local normalizedDate = {
        year = year,
        month = month,
        monthDay = monthDay,
        hour = hour,
        minute = minute,
        weekday = completionDate.weekday,
    }

    if C_DateAndTime and C_DateAndTime.AdjustTimeByMinutes then
        return C_DateAndTime.AdjustTimeByMinutes(normalizedDate, EXMYRUN.TimeOffset * 60)
    end

    return normalizedDate
end

local function EXMYRUN_GetFormattedDate(completionDate)
    if not completionDate then return L["未知"], 0 end

    local adjustedDate = EXMYRUN_GetAdjustedCompletionDate(completionDate)
    if not adjustedDate then
        return L["未知"], 0
    end

    local str = string.format("%02d/%02d %02d:%02d", adjustedDate.month, adjustedDate.monthDay, adjustedDate.hour,
        adjustedDate.minute)
    local sortVal = adjustedDate.year * 100000000 + adjustedDate.month * 1000000 + adjustedDate.monthDay * 10000 +
        adjustedDate.hour * 100 + adjustedDate.minute

    return str, sortVal
end

local function EXMYRUN_GetLevelColorHex(level)
    local colorMixin = C_ChallengeMode.GetKeystoneLevelRarityColor(level)
    return colorMixin and colorMixin:GenerateHexColor() or "ffffffff"
end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local HISTORY_PAGE = EXWIND_MODULE_KEY .. ".History"
local HISTORY_COLUMNS = {
    { title = L["序号"] },
    { title = L["副本 (层数)"] },
    { title = L["日期时间"] },
    { title = L["结果 (时间)"] },
}

local function HistoryCell(id, source)
    return { id = id, kind = "cell", children = {
        { id = id .. ".text", kind = "text", textSource = source },
    } }
end

EXUI:RegisterSettingsPageV2(HISTORY_PAGE, {
    version = 2,
    cards = {{
        id = "history-card", kind = "card", title = L["记录预览"], children = {
            { id = "history-sort", kind = "setting", label = L["排序"], children = {
                { id = "history-sort-key", kind = "control", controlType = "select", ref = "sortKey" },
                { id = "history-sort-direction", kind = "control", controlType = "choice", mode = "single", ref = "sortDirection" },
            } },
            { id = "history-table", kind = "table", columns = HISTORY_COLUMNS, visible = "hasRecords", children = {
                { id = "history-records", kind = "repeat", source = "records", template = {
                    id = "history-record", kind = "row", children = {
                        HistoryCell("history-id", "recordId"),
                        HistoryCell("history-map", "recordMap"),
                        HistoryCell("history-date", "recordDate"),
                        HistoryCell("history-result", "recordResult"),
                    },
                } },
            } },
            { id = "history-filter-empty", kind = "setting", label = L["记录预览"], visible = "filterEmpty",
                description = L["当前筛选条件下没有记录。可在设置中调整筛选条件。"], children = {
                { id = "history-filter-settings", kind = "button", text = L["设置"], action = "openSettings" },
            } },
            { id = "history-empty", kind = "setting", label = L["记录预览"], visible = "empty",
                description = L["本赛季暂无大秘境通关记录。完成大秘境后可在这里查看副本、层数、日期与通关结果。"], children = {
                { id = "history-empty-settings", kind = "button", text = L["设置"], action = "openSettings" },
            } },
        },
    }},
})

function EXMYRUN:CreateHistoryOwner()
    local owner = { controls = {}, actions = {}, predicates = {}, sources = {}, texts = {} }
    owner.sources.records = function() return self.DisplayData end
    owner.predicates.hasRecords = function() return #self.DisplayData > 0 end
    owner.predicates.filterEmpty = function() return #self.DisplayData == 0 and self.RawRecordCount > 0 end
    owner.predicates.empty = function() return self.RawRecordCount == 0 end
    owner.texts.summary = function()
        local filters = {}
        if EX_DB.filterThisWeek then filters[#filters + 1] = L["只看本周记录"] end
        if EX_DB.filterTimed then filters[#filters + 1] = L["只看限时记录"] end
        return string.format(L["记录：%d"], #self.DisplayData)
            .. (#filters > 0 and ("  ·  " .. table.concat(filters, " / ")) or "")
    end
    owner.texts.recordId = function(scope) return tostring(scope.item.originalIndex) end
    owner.texts.recordMap = function(scope)
        local run = scope.item
        local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
        local icon = texture and ("|T" .. texture .. ":" .. EX_DB.size .. ":" .. EX_DB.size .. ":0:0:64:64:5:59:5:59|t ") or ""
        local color = EXMYRUN_GetLevelColorHex(run.level)
        return icon .. "|c" .. color .. (mapName or L["未知副本"]) .. " (+" .. run.level .. ")|r"
    end
    owner.texts.recordDate = function(scope) return scope.item.dateStr end
    owner.texts.recordResult = function(scope)
        local run = scope.item
        if run.hasData then
            local difference = EXMYRUN_FormatTime(math.abs(run.durationSec - run.timeLimit))
            if run.isTimed then
                return string.format("|cff00ff00" .. L["限时 (剩%s)"] .. "|r", difference)
            elseif run.isOverTime then
                return string.format("|cffff0000" .. L["超时 (超%s)"] .. "|r", difference)
            end
        end
        return "|cff999999" .. L["无时间记录"] .. "|r"
    end
    owner.controls.sortKey = EXUI:CreateSettingsV2Control({ controlType = "select", options = {
        { label = L["序号"], value = "id" },
        { label = L["副本 (层数)"], value = "map" },
        { label = L["日期时间"], value = "date" },
    } }, function() return EXUI:CreateSettingsV2Binding(EXWIND_MODULE_KEY, self.SortState, "key") end)
    owner.controls.sortDirection = EXUI:CreateSettingsV2Control({ controlType = "segment", options = {
        { label = "↑", value = 1 }, { label = "↓", value = -1 },
    } }, function() return {
        Read = function() return self.SortState.asc and 1 or -1 end,
        Write = function(_, value)
            self.SortState.asc = value == 1
            self:UpdateList()
        end,
    } end)
    owner.actions.openSettings = function() ExwindTools:OpenConfig(EXWIND_MODULE_KEY) end
    owner.onHeightChanged = function(height)
        self.MainFrame.ScrollChild:SetHeight(math.max(1, height))
        self.MainFrame.Scroll:UpdateScrollChildRect()
    end
    return owner
end

-- 窗口几何仍由本模块持有，记录正文由正式 V2 会话持有。
function EXMYRUN:CreateMainFrame()
    local f = CreateFrame("Frame", "EXMYRUNMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(self.FrameWidth, self.FrameHeight)

    if EX_DB.point then
        f:SetPoint(EX_DB.point, UIParent, EX_DB.relativePoint, EX_DB.xOfs, EX_DB.yOfs)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(f:GetFrameLevel() + 101)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        EX_DB.point = point
        EX_DB.relativePoint = relativePoint
        EX_DB.xOfs = xOfs
        EX_DB.yOfs = yOfs
    end)

    local colors = ExwindTools.GUIColors
    EXUI:SetControlSurface(f, ExwindTools.GUIMetrics.radius.card, colors.panel, colors.panelBorder)

    f.Title = EXUI:CreateVisualFontString(f, _G.EXFONTFRAME, "GameFontNormalLarge")
    f.Title:SetPoint("TOPLEFT", 12, -10)
    f.Title:SetTextColor(unpack(colors.text))
    f.Title:SetText(L["大秘境赛季记录"])

    -- 关闭按钮
    f.CloseButton = EXUI:CreateButton(f, 26, 26, "×", function() f:Hide() end,
        { compact = true, variant = "danger" })
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)

    f.SettingsButton = EXUI:CreateButton(f, 64, 26, L["设置"],
        function() ExwindTools:OpenConfig(EXWIND_MODULE_KEY) end, { compact = true })
    f.SettingsButton:SetPoint("RIGHT", f.CloseButton, "LEFT", -8, 0)
    f.Summary = EXUI:CreateVisualFontString(f, _G.EXFONTFRAME, "GameFontHighlightSmall")
    f.Summary:SetPoint("LEFT", f.Title, "RIGHT", 12, 0)
    f.Summary:SetPoint("RIGHT", f.SettingsButton, "LEFT", -12, 0)
    f.Summary:SetJustifyH("LEFT")
    f.Summary:SetWordWrap(false)
    f.Summary:SetTextColor(unpack(colors.text))

    f.Scroll = EXUI:CreateScrollFrame(f, "EXMYRUNHistoryScroll")
    f.Scroll:SetPoint("TOPLEFT", 4, -38)
    f.Scroll:SetPoint("BOTTOMRIGHT", -EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET, 4)

    f.ScrollChild = CreateFrame("Frame", nil, f.Scroll)
    f.ScrollChild:SetSize(f.Scroll:GetWidth(), 1)
    f.Scroll:SetScrollChild(f.ScrollChild)

    self.MainFrame = f
    self.HistoryOwner = self:CreateHistoryOwner()
    f.Scroll:HookScript("OnSizeChanged", function(scroll)
        f.ScrollChild:SetWidth(scroll:GetWidth())
    end)
    f:SetScript("OnHide", function()
        if self.HistorySession then
            self.HistorySession:Release()
            self.HistorySession = nil
        end
    end)
    f:Hide()
end

function EXMYRUN:UpdateList()
    if not self.MainFrame then return end

    local rawData = C_MythicPlus.GetRunHistory(true, true, true)
    self.RawRecordCount = #rawData
    local displayData = {}

    for i, run in ipairs(rawData) do
        local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
        local isTimed, isOverTime, hasData = false, false, false

        if run.durationSec and run.durationSec > 0 and timeLimit and timeLimit > 0 then
            hasData = true
            if run.durationSec <= timeLimit then
                isTimed = true
            else
                isOverTime = true
            end
        end

        local pass = true
        if EX_DB.filterThisWeek and not run.thisWeek then pass = false end
        if EX_DB.filterTimed and not isTimed then pass = false end

        if pass then
            run.originalIndex = i
            local mapName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
            run.mapNameSort = mapName or ""
            local str, sortVal = EXMYRUN_GetFormattedDate(run.completionDate)
            run.dateStr = str
            run.dateSort = sortVal
            run.isTimed = isTimed
            run.isOverTime = isOverTime
            run.timeLimit = timeLimit
            run.hasData = hasData
            table.insert(displayData, run)
        end
    end

    -- [Safety] 确保数据表紧凑，无 nil 空洞
    local compactData = {}
    for _, v in pairs(displayData) do
        if v then table.insert(compactData, v) end
    end
    displayData = compactData

    table.sort(displayData, function(a, b)
        if not a or not b then return false end
        local k = self.SortState.key
        local asc = self.SortState.asc

        if k == "id" then
            if a.originalIndex == b.originalIndex then return false end
            if asc then return a.originalIndex < b.originalIndex else return a.originalIndex > b.originalIndex end
        elseif k == "map" then
            if a.mapNameSort ~= b.mapNameSort then
                if asc then return a.mapNameSort < b.mapNameSort else return a.mapNameSort > b.mapNameSort end
            end
            if a.level ~= b.level then return a.level > b.level end
            return a.originalIndex < b.originalIndex
        elseif k == "date" then
            local aSort = a.dateSort or 0
            local bSort = b.dateSort or 0
            if aSort ~= bSort then
                if asc then return aSort < bSort else return aSort > bSort end
            end
            return a.originalIndex < b.originalIndex
        end
        return a.originalIndex < b.originalIndex
    end)

    self.DisplayData = displayData
    self.MainFrame.Summary:SetText(self.HistoryOwner.texts.summary())
    if self.HistorySession then
        self.HistorySession:Refresh()
    elseif self.MainFrame:IsShown() then
        self.HistorySession = EXUI:MountSettingsPageV2(self.MainFrame.ScrollChild, HISTORY_PAGE, self.HistoryOwner)
    end
end

function EXMYRUN:ToggleWindow()
    if not self.MainFrame then
        self:CreateMainFrame()
    end
    if self.MainFrame:IsShown() then
        self.MainFrame:Hide()
    else
        self.MainFrame:Show()
        self:UpdateList()
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
-- 注册斜杠命令
SLASH_EXMYRUN1 = "/emr"
SLASH_EXMYRUN2 = "/exmythicrun"
SlashCmdList["EXMYRUN"] = function()
    EXMYRUN:ToggleWindow()
end

local function RefreshActiveSurfaces()
    EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXMYRUN_DEFAULTS)
    if EXMYRUN.MainFrame and EXMYRUN.MainFrame:IsShown() then EXMYRUN:UpdateList() end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
