-- GuildBridge UI Module
-- Handles all UI elements including main frame, tabs, and dialogs

local addonName, GB = ...

-- Forward declarations for local functions
local updateTabHighlights
local updatePageTabSelection
local updatePageVisibility
local createTab
local createPageTab
local showContextMenu
local showRealmInputDialog

-- Context menu and dialog frames (created on demand)
local contextMenu
local forgetButton
local setRealmButton
local realmInputDialog
local allTabContextMenu
local forgetAllButton

-- Update tab highlights based on current filter
updateTabHighlights = function()
    for _, tab in pairs(GB.tabButtons) do
        if tab.filterValue == GB.currentFilter then
            tab.guildText:SetFontObject(GameFontHighlight)
            tab.guildText:SetTextColor(1, 0.82, 0)
            tab.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
            tab.border:SetColorTexture(0.8, 0.6, 0.2, 1)
            if tab.realmText then
                tab.realmText:SetTextColor(0.7, 0.7, 0.7)
            end
            tab.selected = true
        else
            tab.guildText:SetFontObject(GameFontNormal)
            tab.guildText:SetTextColor(0.8, 0.8, 0.8)
            tab.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            tab.border:SetColorTexture(0.3, 0.3, 0.3, 1)
            if tab.realmText then
                tab.realmText:SetTextColor(0.5, 0.5, 0.5)
            end
            tab.selected = false
        end
    end
end

-- Update connection status indicators on guild tabs
function GB:UpdateConnectionIndicators()
    -- Get my guild's filterKey to check if a tab is my own guild
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = self:GetGuildHomeRealm()
    local myFilterKey = nil
    if myGuildName then
        if myGuildClubId then
            myFilterKey = myGuildName .. "-" .. myGuildClubId
        elseif myGuildHomeRealm then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
    end

    for _, tab in pairs(self.tabButtons) do
        if tab.statusDot and tab.guildName then
            -- If this tab is my own guild, always show green (I'm always connected to my own guild)
            -- Only match on filterKey - guildName alone is not unique (same guild name on different realms)
            local isMyGuild = (tab.filterValue == myFilterKey)
            if isMyGuild then
                tab.statusDot:SetColorTexture(0.3, 0.8, 0.3, 1)
            elseif self:HasConnectedUserInGuild(tab.filterValue) then
                -- Has a bridge user connected in this guild - green
                tab.statusDot:SetColorTexture(0.3, 0.8, 0.3, 1)
            else
                -- No confirmed bridge user in this guild - red
                tab.statusDot:SetColorTexture(0.8, 0.3, 0.3, 1)
            end
        end
    end
end

-- Forget a guild from known guilds
local function forgetGuild(filterKey)
    if not filterKey then return end
    GB.knownGuilds[filterKey] = nil
    GuildBridgeDB.knownGuilds = GB.knownGuilds
    if GB.currentFilter == filterKey then
        GB.currentFilter = nil
    end
    GB:RebuildTabs()
    GB:RefreshMessages()
end

-- Set guild realm display name
local function setGuildRealm(filterKey, newRealm)
    -- Update the specific guild entry by filterKey
    if filterKey and GB.knownGuilds[filterKey] then
        GB.knownGuilds[filterKey].realmName = newRealm
        GB.knownGuilds[filterKey].manualRealm = true  -- Mark as manually set
        GuildBridgeDB.knownGuilds = GB.knownGuilds
        GB:RebuildTabs()
    end
end

-- Show realm input dialog
showRealmInputDialog = function(filterKey, guildName)
    if not realmInputDialog then
        realmInputDialog = CreateFrame("Frame", "GuildBridgeRealmDialog", UIParent, "BackdropTemplate")
        realmInputDialog:SetSize(220, 90)
        realmInputDialog:SetPoint("CENTER")
        realmInputDialog:SetFrameStrata("DIALOG")
        realmInputDialog:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        realmInputDialog:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        realmInputDialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        realmInputDialog:EnableMouse(true)
        realmInputDialog:SetMovable(true)
        realmInputDialog:RegisterForDrag("LeftButton")
        realmInputDialog:SetScript("OnDragStart", realmInputDialog.StartMoving)
        realmInputDialog:SetScript("OnDragStop", realmInputDialog.StopMovingOrSizing)

        realmInputDialog.title = realmInputDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        realmInputDialog.title:SetPoint("TOP", 0, -10)
        realmInputDialog.title:SetText("Set Realm")

        realmInputDialog.editBox = CreateFrame("EditBox", nil, realmInputDialog, "InputBoxTemplate")
        realmInputDialog.editBox:SetSize(180, 20)
        realmInputDialog.editBox:SetPoint("TOP", realmInputDialog.title, "BOTTOM", 0, -10)
        realmInputDialog.editBox:SetAutoFocus(true)

        realmInputDialog.okButton = CreateFrame("Button", nil, realmInputDialog, "UIPanelButtonTemplate")
        realmInputDialog.okButton:SetSize(60, 22)
        realmInputDialog.okButton:SetPoint("BOTTOMRIGHT", realmInputDialog, "BOTTOM", -5, 10)
        realmInputDialog.okButton:SetText("OK")

        realmInputDialog.cancelButton = CreateFrame("Button", nil, realmInputDialog, "UIPanelButtonTemplate")
        realmInputDialog.cancelButton:SetSize(60, 22)
        realmInputDialog.cancelButton:SetPoint("BOTTOMLEFT", realmInputDialog, "BOTTOM", 5, 10)
        realmInputDialog.cancelButton:SetText("Cancel")
        realmInputDialog.cancelButton:SetScript("OnClick", function()
            realmInputDialog:Hide()
        end)

        realmInputDialog.editBox:SetScript("OnEscapePressed", function()
            realmInputDialog:Hide()
        end)

        realmInputDialog:Hide()
    end

    realmInputDialog.title:SetText("Set Realm for " .. guildName)
    realmInputDialog.editBox:SetText("")

    realmInputDialog.editBox:SetScript("OnEnterPressed", function(self)
        local realm = self:GetText()
        if realm and realm ~= "" then
            setGuildRealm(realmInputDialog.filterKey, realm)
        end
        realmInputDialog:Hide()
    end)

    realmInputDialog.okButton:SetScript("OnClick", function()
        local realm = realmInputDialog.editBox:GetText()
        if realm and realm ~= "" then
            setGuildRealm(realmInputDialog.filterKey, realm)
        end
        realmInputDialog:Hide()
    end)

    realmInputDialog.filterKey = filterKey
    realmInputDialog:Show()
    realmInputDialog.editBox:SetFocus()
end

-- Ensure context menu is created
local function ensureContextMenu()
    if contextMenu then return end

    contextMenu = CreateFrame("Frame", "GuildBridgeContextMenu", UIParent, "BackdropTemplate")
    contextMenu:SetSize(120, 72)
    contextMenu:SetFrameStrata("DIALOG")
    contextMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    contextMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    contextMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    contextMenu:Hide()

    setRealmButton = CreateFrame("Button", nil, contextMenu)
    setRealmButton:SetSize(110, 20)
    setRealmButton:SetPoint("TOP", contextMenu, "TOP", 0, -8)
    setRealmButton.text = setRealmButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    setRealmButton.text:SetPoint("CENTER")
    setRealmButton.text:SetText("Set Realm")
    setRealmButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    setRealmButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    setRealmButton.text:SetTextColor(1, 0.82, 0)

    forgetButton = CreateFrame("Button", nil, contextMenu)
    forgetButton:SetSize(110, 20)
    forgetButton:SetPoint("TOP", setRealmButton, "BOTTOM", 0, -2)
    forgetButton.text = forgetButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    forgetButton.text:SetPoint("CENTER")
    forgetButton.text:SetText("Forget")
    forgetButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    forgetButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    forgetButton.text:SetTextColor(1, 0.82, 0)

    local cancelButton = CreateFrame("Button", nil, contextMenu)
    cancelButton:SetSize(110, 20)
    cancelButton:SetPoint("TOP", forgetButton, "BOTTOM", 0, -2)
    cancelButton.text = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelButton.text:SetPoint("CENTER")
    cancelButton.text:SetText("Cancel")
    cancelButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7)
    end)
    cancelButton.text:SetTextColor(0.7, 0.7, 0.7)
    cancelButton:SetScript("OnClick", function()
        contextMenu:Hide()
    end)

    contextMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    contextMenu:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    contextMenu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if not MouseIsOver(self) and not (realmInputDialog and realmInputDialog:IsShown()) then
                self:Hide()
            end
        end
    end)
    contextMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

-- Show context menu for a guild tab
showContextMenu = function(filterKey, guildLabel, guildName)
    ensureContextMenu()
    setRealmButton:SetScript("OnClick", function()
        contextMenu:Hide()
        showRealmInputDialog(filterKey, guildName)
    end)
    forgetButton.text:SetText("Forget " .. guildLabel)
    forgetButton:SetScript("OnClick", function()
        forgetGuild(filterKey)
        contextMenu:Hide()
    end)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    contextMenu:ClearAllPoints()
    contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    contextMenu:Show()
end

-- Forget all guilds (except own guild)
local function forgetAllGuilds()
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = GB:GetGuildHomeRealm()
    local myFilterKey = nil
    if myGuildName then
        if myGuildClubId then
            myFilterKey = myGuildName .. "-" .. myGuildClubId
        elseif myGuildHomeRealm then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
    end

    -- Clear all guilds except own guild
    for filterKey, _ in pairs(GB.knownGuilds) do
        if filterKey ~= myFilterKey then
            GB.knownGuilds[filterKey] = nil
        end
    end
    GuildBridgeDB.knownGuilds = GB.knownGuilds

    -- Reset filter if needed
    GB.currentFilter = nil
    GB:RebuildTabs()
    GB:RefreshMessages()
end

-- Ensure All tab context menu is created
local function ensureAllTabContextMenu()
    if allTabContextMenu then return end

    allTabContextMenu = CreateFrame("Frame", "GuildBridgeAllTabContextMenu", UIParent, "BackdropTemplate")
    allTabContextMenu:SetSize(120, 50)
    allTabContextMenu:SetFrameStrata("DIALOG")
    allTabContextMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    allTabContextMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    allTabContextMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    allTabContextMenu:Hide()

    forgetAllButton = CreateFrame("Button", nil, allTabContextMenu)
    forgetAllButton:SetSize(110, 20)
    forgetAllButton:SetPoint("TOP", allTabContextMenu, "TOP", 0, -8)
    forgetAllButton.text = forgetAllButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    forgetAllButton.text:SetPoint("CENTER")
    forgetAllButton.text:SetText("Forget All Guilds")
    forgetAllButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    forgetAllButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    forgetAllButton.text:SetTextColor(1, 0.82, 0)
    forgetAllButton:SetScript("OnClick", function()
        forgetAllGuilds()
        allTabContextMenu:Hide()
    end)

    local cancelButton = CreateFrame("Button", nil, allTabContextMenu)
    cancelButton:SetSize(110, 20)
    cancelButton:SetPoint("TOP", forgetAllButton, "BOTTOM", 0, -2)
    cancelButton.text = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelButton.text:SetPoint("CENTER")
    cancelButton.text:SetText("Cancel")
    cancelButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7)
    end)
    cancelButton.text:SetTextColor(0.7, 0.7, 0.7)
    cancelButton:SetScript("OnClick", function()
        allTabContextMenu:Hide()
    end)

    allTabContextMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    allTabContextMenu:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    allTabContextMenu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if not MouseIsOver(self) then
                self:Hide()
            end
        end
    end)
    allTabContextMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

-- Show context menu for All tab
local function showAllTabContextMenu()
    ensureAllTabContextMenu()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    allTabContextMenu:ClearAllPoints()
    allTabContextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    allTabContextMenu:Show()
end

-- Create a guild filter tab
createTab = function(parent, guildLabel, realmLabel, filterValue, xOffset, yOffset, guildName, tabWidth)
    tabWidth = tabWidth or 72
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetSize(tabWidth, 34)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    tab:SetFrameLevel(parent:GetFrameLevel() + 10)
    tab:EnableMouse(true)
    tab.filterValue = filterValue
    tab.guildName = guildName

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    tab.bg = bg

    local border = tab:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    tab.border = border

    if guildName then
        tab.statusDot = tab:CreateTexture(nil, "OVERLAY")
        tab.statusDot:SetSize(8, 8)
        tab.statusDot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -3, -3)
    end

    tab.guildText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if realmLabel and realmLabel ~= "" then
        tab.guildText:SetPoint("TOP", tab, "TOP", 0, -5)
    else
        tab.guildText:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
    tab.guildText:SetText(guildLabel)

    if realmLabel and realmLabel ~= "" then
        tab.realmText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
        tab.realmText:SetPoint("TOP", tab.guildText, "BOTTOM", 0, -2)
        tab.realmText:SetText(realmLabel)
        tab.realmText:SetTextColor(0.5, 0.5, 0.5)
    end

    tab:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            if filterValue and guildName then
                showContextMenu(filterValue, guildLabel, guildName)
            elseif not filterValue and guildLabel == "All" then
                -- Right-click on All tab
                showAllTabContextMenu()
            end
        elseif button == "LeftButton" then
            GB.currentFilter = filterValue
            updateTabHighlights()
            GB:RefreshMessages()
        end
    end)

    tab:SetScript("OnEnter", function(self)
        if not self.selected then
            self.guildText:SetTextColor(1, 1, 1)
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
            self.border:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.selected then
            self.guildText:SetTextColor(0.8, 0.8, 0.8)
            self.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            self.border:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
    end)

    return tab
end

-- Update page tab selection (Chat vs Status)
updatePageTabSelection = function()
    for i, tab in ipairs(GB.pageTabs) do
        if tab.pageName == GB.currentPage then
            -- Selected tab
            tab.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
            tab.border:SetColorTexture(0.8, 0.6, 0.2, 1)
            tab.text:SetTextColor(1, 0.82, 0)
        else
            -- Unselected tab
            tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            tab.border:SetColorTexture(0.4, 0.4, 0.4, 1)
            tab.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

-- Create a styled page tab (Chat/Status)
createPageTab = function(parent, label, tabIndex, pageName)
    local tab = CreateFrame("Button", "GuildBridgePageTab" .. tabIndex, parent)
    tab:SetSize(60, 24)
    tab:SetID(tabIndex)
    tab.pageName = pageName

    -- Background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    -- Border
    tab.border = tab:CreateTexture(nil, "BORDER")
    tab.border:SetPoint("TOPLEFT", -1, 1)
    tab.border:SetPoint("BOTTOMRIGHT", 1, -1)
    tab.border:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- Text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(label)

    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        GB.currentPage = self.pageName
        updatePageVisibility()
    end)

    tab:SetScript("OnEnter", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
            self.text:SetTextColor(1, 1, 1)
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            self.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end)

    return tab
end

-- Create page tabs (Chat and Status)
local function createPageTabs()
    if not GB.mainFrame then return end

    -- Clear existing page tabs
    for _, tab in pairs(GB.pageTabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    GB.pageTabs = {}

    -- Create Chat tab at top left (below title bar)
    GB.pageTabs[1] = createPageTab(GB.mainFrame, "Chat", 1, "chat")
    GB.pageTabs[1]:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 10, -24)

    -- Create Status tab next to Chat
    GB.pageTabs[2] = createPageTab(GB.mainFrame, "Status", 2, "status")
    GB.pageTabs[2]:SetPoint("LEFT", GB.pageTabs[1], "RIGHT", 4, 0)

    updatePageTabSelection()
end

-- Update page visibility (show/hide elements based on current page)
updatePageVisibility = function()
    if not GB.mainFrame then return end

    -- Hide/show guild filter tabs based on current page
    for key, tab in pairs(GB.tabButtons) do
        if key:match("^guild") or key == "all" then
            if GB.currentPage == "chat" then
                tab:Show()
            else
                tab:Hide()
            end
        end
    end

    -- Update page tab selection (native WoW style)
    updatePageTabSelection()

    -- Adjust scroll frame position
    if GB.scrollFrame then
        local pageTabHeight = 28  -- Height of page tabs + spacing
        if GB.currentPage == "chat" then
            -- Calculate guild tab rows
            local tabWidth = 72
            local tabSpacing = 4
            local rowHeight = 38
            local maxWidth = GB.mainFrame:GetWidth() - 16
            -- Count: "All" tab + all known guilds (including own guild now)
            local guildCount = 1  -- Start with 1 for "All" tab
            for _ in pairs(GB.knownGuilds) do
                guildCount = guildCount + 1
            end
            local tabsPerRow = math.floor(maxWidth / (tabWidth + tabSpacing))
            local numRows = math.ceil(guildCount / tabsPerRow)
            if numRows < 1 then numRows = 1 end
            -- Page tabs + guild filter rows
            local scrollTopOffset = 24 + pageTabHeight + (numRows * rowHeight)
            GB.scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        else
            -- Status page - just page tabs, no guild filter tabs
            local scrollTopOffset = 24 + pageTabHeight
            GB.scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        end
    end

    GB:RefreshMessages()
end

-- Rebuild guild filter tabs
function GB:RebuildTabs()
    if not self.mainFrame then return end

    for key, tab in pairs(self.tabButtons) do
        tab:Hide()
        tab:SetParent(nil)
    end
    self.tabButtons = {}

    local tabSpacing = 4
    local tabWidth = 72
    local rowHeight = 38
    local pageTabHeight = 28
    local topRowY = -(24 + pageTabHeight)  -- Below title bar and page tabs

    -- Guild filter tabs (only visible on chat page)
    local myGuildName = GetGuildInfo("player")
    local xOffset = 8
    local yOffset = topRowY
    local maxWidth = self.mainFrame:GetWidth() - 16
    local tabIndex = 1

    -- "All" tab for chat page
    self.tabButtons.all = createTab(self.mainFrame, "All", nil, nil, xOffset, yOffset, nil, tabWidth)
    xOffset = xOffset + tabWidth + tabSpacing

    -- Get my guild's filterKey
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = self:GetGuildHomeRealm()
    local myFilterKey = nil
    if myGuildName then
        if myGuildClubId then
            myFilterKey = myGuildName .. "-" .. myGuildClubId
        elseif myGuildHomeRealm then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
    end

    -- Show my own guild first (right after "All" tab)
    if myFilterKey and self.knownGuilds[myFilterKey] then
        local info = self.knownGuilds[myFilterKey]
        local short = self.guildShortNames[info.guildName] or info.guildName or "?"
        -- Append guild number if configured
        local guildNum = self:GetGuildNumber(info.guildName, info.guildHomeRealm)
        if guildNum then
            short = short .. " " .. guildNum
        end
        local realmLabel = nil
        if info.manualRealm and info.realmName then
            realmLabel = info.realmName
        elseif info.guildHomeRealm then
            realmLabel = info.guildHomeRealm
        end
        self.tabButtons["guild" .. tabIndex] = createTab(self.mainFrame, short, realmLabel, myFilterKey, xOffset, yOffset, info.guildName, tabWidth)
        xOffset = xOffset + tabWidth + tabSpacing
        tabIndex = tabIndex + 1
    end

    -- Then show other guilds
    for filterKey, info in pairs(self.knownGuilds) do
        -- Skip my own guild (already shown first)
        if filterKey ~= myFilterKey then
            -- Check if we need to wrap to next row
            if xOffset + tabWidth > maxWidth then
                xOffset = 8
                yOffset = yOffset - rowHeight
            end

            local short = self.guildShortNames[info.guildName] or info.guildName or "?"
            -- Append guild number if configured
            local guildNum = self:GetGuildNumber(info.guildName, info.guildHomeRealm)
            if guildNum then
                short = short .. " " .. guildNum
            end
            -- Show manually set realm if available, otherwise show guild home realm (from GM)
            local realmLabel = nil
            if info.manualRealm and info.realmName then
                realmLabel = info.realmName
            elseif info.guildHomeRealm then
                realmLabel = info.guildHomeRealm
            end
            self.tabButtons["guild" .. tabIndex] = createTab(self.mainFrame, short, realmLabel, filterKey, xOffset, yOffset, info.guildName, tabWidth)
            xOffset = xOffset + tabWidth + tabSpacing
            tabIndex = tabIndex + 1
        end
    end

    updatePageVisibility()
    updateTabHighlights()
    self:UpdateConnectionIndicators()
end

-- Create the main bridge UI
function GB:CreateBridgeUI()
    if self.mainFrame then
        return
    end

    self.mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    self.mainFrame:SetSize(420, 300)
    self.mainFrame:SetPoint("CENTER")
    self.mainFrame:SetMovable(true)
    self.mainFrame:EnableMouse(true)
    self.mainFrame:RegisterForDrag("LeftButton")
    self.mainFrame:SetScript("OnDragStart", self.mainFrame.StartMoving)
    self.mainFrame:SetScript("OnDragStop", self.mainFrame.StopMovingOrSizing)

    self.mainFrame.title = self.mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.mainFrame.title:SetPoint("LEFT", self.mainFrame.TitleBg, "LEFT", 5, 0)
    self.mainFrame.title:SetText("Guild Bridge")

    -- Create native WoW-style page tabs at the bottom
    createPageTabs()

    self:RebuildTabs()

    self.muteCheckbox = CreateFrame("CheckButton", nil, self.mainFrame, "UICheckButtonTemplate")
    self.muteCheckbox:SetSize(24, 24)
    self.muteCheckbox:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -10, -22)
    self.muteCheckbox.text = self.muteCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.muteCheckbox.text:SetPoint("RIGHT", self.muteCheckbox, "LEFT", -2, 0)
    self.muteCheckbox.text:SetText("Mute Send")
    self.muteCheckbox:SetChecked(GuildBridgeDB.muteSend or false)
    self.muteCheckbox:SetScript("OnClick", function(checkbox)
        GuildBridgeDB.muteSend = checkbox:GetChecked()
    end)

    local filterChatCheckbox = CreateFrame("CheckButton", nil, self.mainFrame, "UICheckButtonTemplate")
    filterChatCheckbox:SetSize(24, 24)
    filterChatCheckbox:SetPoint("RIGHT", self.muteCheckbox.text, "LEFT", -10, 0)
    filterChatCheckbox.text = filterChatCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterChatCheckbox.text:SetPoint("RIGHT", filterChatCheckbox, "LEFT", -2, 0)
    filterChatCheckbox.text:SetText("Filter Native Chat Also")
    filterChatCheckbox:SetChecked(GuildBridgeDB.filterNativeChat or false)
    filterChatCheckbox:SetScript("OnClick", function(checkbox)
        GuildBridgeDB.filterNativeChat = checkbox:GetChecked()
    end)

    self.scrollFrame = CreateFrame("ScrollingMessageFrame", nil, self.mainFrame)
    self.scrollFrame:SetPoint("TOPLEFT", 10, -90)  -- Default: page tabs (28) + 1 row of guild filter tabs (38) + title bar (24)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    self.scrollFrame:SetFontObject(GameFontHighlightSmall)
    self.scrollFrame:SetJustifyH("LEFT")
    self.scrollFrame:SetFading(false)
    self.scrollFrame:SetMaxLines(500)
    self.scrollFrame:EnableMouseWheel(true)
    self.scrollFrame:SetHyperlinksEnabled(true)
    self.scrollFrame:SetScript("OnMouseWheel", function(scrollFrame, delta)
        if delta > 0 then
            scrollFrame:ScrollUp()
        elseif delta < 0 then
            scrollFrame:ScrollDown()
        end
    end)
    self.scrollFrame:SetScript("OnHyperlinkClick", function(scrollFrame, link, text, button)
        SetItemRef(link, text, button)
    end)

    self.inputBox = CreateFrame("EditBox", nil, self.mainFrame, "InputBoxTemplate")
    self.inputBox:SetPoint("BOTTOMLEFT", 10, 10)
    self.inputBox:SetPoint("BOTTOMRIGHT", -10, 10)
    self.inputBox:SetHeight(20)
    self.inputBox:SetAutoFocus(false)
    self.inputBox:SetFontObject(GameFontHighlightSmall)

    self.inputBox:SetScript("OnEnterPressed", function(inputBox)
        local text = inputBox:GetText()
        GB:SendFromUI(text)
        inputBox:SetText("")
    end)

    self.inputBox:SetScript("OnEscapePressed", function(inputBox)
        inputBox:ClearFocus()
    end)

    self.mainFrame:Hide()
end

-- Toggle bridge frame visibility
function GB:ToggleBridgeFrame()
    if not self.mainFrame then
        return
    end
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
    end
end
