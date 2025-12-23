-- GuildBridge UI Module
-- Handles all UI elements including main frame, tabs, and dialogs

local addonName, GB = ...

-- UI Constants
local MIN_WIDTH = 380
local MIN_HEIGHT = 280
local DEFAULT_WIDTH = 480
local DEFAULT_HEIGHT = 380

-- Guild-style color scheme (warmer, easier on eyes)
local COLORS = {
    -- Backgrounds - warm dark tones like native WoW frames
    bgDark = { 0.05, 0.05, 0.06, 0.92 },
    bgMedium = { 0.08, 0.08, 0.09, 0.90 },
    bgLight = { 0.12, 0.12, 0.13, 0.85 },
    bgChat = { 0.03, 0.03, 0.04, 0.75 },  -- Chat area background

    -- Borders - subtle warm gray
    border = { 0.20, 0.18, 0.16, 0.8 },
    borderLight = { 0.30, 0.28, 0.25, 0.6 },
    borderHighlight = { 0.45, 0.40, 0.35, 1 },

    -- Guild green accent (matches guild chat)
    guildGreen = { 0.25, 1.0, 0.25, 1 },
    guildGreenDark = { 0.15, 0.5, 0.15, 1 },
    guildGreenMuted = { 0.20, 0.45, 0.20, 1 },

    -- Gold for selected items
    accentGold = { 1, 0.82, 0, 1 },
    accentGoldDim = { 0.8, 0.65, 0, 0.8 },

    -- Text colors
    textNormal = { 0.90, 0.88, 0.85, 1 },
    textMuted = { 0.55, 0.52, 0.48, 1 },
    textHighlight = { 1, 1, 1, 1 },
    textGuild = { 0.25, 1.0, 0.25, 1 },   -- Guild chat green

    -- Tab colors
    tabNormal = { 0.10, 0.10, 0.11, 0.85 },
    tabSelected = { 0.12, 0.14, 0.12, 0.95 },
    tabHover = { 0.15, 0.17, 0.15, 0.90 },

    -- Status indicators
    statusGreen = { 0.2, 0.9, 0.2, 1 },
    statusRed = { 0.9, 0.25, 0.25, 1 },
    statusYellow = { 0.9, 0.8, 0.2, 1 },

    -- Input
    inputBg = { 0.06, 0.06, 0.07, 0.9 },
    inputBorder = { 0.25, 0.35, 0.25, 0.8 },
}

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
            -- Selected tab - guild green text with subtle green-tinted background
            tab.guildText:SetTextColor(unpack(COLORS.guildGreen))
            tab.bg:SetColorTexture(unpack(COLORS.tabSelected))
            tab.borderTop:SetColorTexture(COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3], 0.9)
            if tab.realmText then
                tab.realmText:SetTextColor(0.6, 0.75, 0.6, 1)
            end
            tab.selected = true
        else
            tab.guildText:SetTextColor(unpack(COLORS.textNormal))
            tab.bg:SetColorTexture(unpack(COLORS.tabNormal))
            tab.borderTop:SetColorTexture(0, 0, 0, 0)
            if tab.realmText then
                tab.realmText:SetTextColor(unpack(COLORS.textMuted))
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
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
            elseif self:HasConnectedUserInGuild(tab.filterValue) then
                -- Has a bridge user connected in this guild - green
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
            else
                -- No confirmed bridge user in this guild - red
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Red")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusRed))
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

-- Create a guild filter tab with modern styling
createTab = function(parent, guildLabel, realmLabel, filterValue, xOffset, yOffset, guildName, tabWidth)
    tabWidth = tabWidth or 80
    local tabHeight = 34
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetSize(tabWidth, tabHeight)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    tab:SetFrameLevel(parent:GetFrameLevel() + 10)
    tab:EnableMouse(true)
    tab.filterValue = filterValue
    tab.guildName = guildName

    -- Background
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(unpack(COLORS.tabNormal))
    tab.bg = bg

    -- Top accent border (shows when selected) - guild green
    local borderTop = tab:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", 0, 0)
    borderTop:SetHeight(2)
    borderTop:SetColorTexture(0, 0, 0, 0)
    tab.borderTop = borderTop

    -- Subtle side borders
    local borderLeft = tab:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(unpack(COLORS.borderLight))

    local borderRight = tab:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(unpack(COLORS.borderLight))

    -- Bottom border
    local borderBottom = tab:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(unpack(COLORS.borderLight))
    tab.borderBottom = borderBottom

    -- Status indicator dot (for guild tabs) - larger and more visible
    if guildName then
        tab.statusDot = tab:CreateTexture(nil, "OVERLAY")
        tab.statusDot:SetSize(14, 14)
        tab.statusDot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -3, -3)
        tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
        tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
    end

    -- Guild name text
    tab.guildText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if realmLabel and realmLabel ~= "" then
        tab.guildText:SetPoint("TOP", tab, "TOP", 0, -7)
    else
        tab.guildText:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
    tab.guildText:SetText(guildLabel)
    tab.guildText:SetTextColor(unpack(COLORS.textNormal))

    -- Realm name text (smaller, muted)
    if realmLabel and realmLabel ~= "" then
        tab.realmText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
        tab.realmText:SetPoint("TOP", tab.guildText, "BOTTOM", 0, -2)
        tab.realmText:SetText(realmLabel)
        tab.realmText:SetTextColor(unpack(COLORS.textMuted))
    end

    tab:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            if filterValue and guildName then
                showContextMenu(filterValue, guildLabel, guildName)
            elseif not filterValue and guildLabel == "All" then
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
            self.guildText:SetTextColor(unpack(COLORS.guildGreen))
            self.bg:SetColorTexture(unpack(COLORS.tabHover))
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.selected then
            self.guildText:SetTextColor(unpack(COLORS.textNormal))
            self.bg:SetColorTexture(unpack(COLORS.tabNormal))
        end
    end)

    return tab
end

-- Update page tab selection (Chat vs Status)
updatePageTabSelection = function()
    for i, tab in ipairs(GB.pageTabs) do
        if tab.pageName == GB.currentPage then
            -- Selected tab - guild green accent
            tab.bg:SetColorTexture(unpack(COLORS.tabSelected))
            tab.borderBottom:SetColorTexture(unpack(COLORS.guildGreen))
            tab.text:SetTextColor(unpack(COLORS.guildGreen))
        else
            -- Unselected tab
            tab.bg:SetColorTexture(unpack(COLORS.bgDark))
            tab.borderBottom:SetColorTexture(unpack(COLORS.borderLight))
            tab.text:SetTextColor(unpack(COLORS.textMuted))
        end
    end
end

-- Create a styled page tab (Chat/Status)
createPageTab = function(parent, label, tabIndex, pageName)
    local tab = CreateFrame("Button", "GuildBridgePageTab" .. tabIndex, parent)
    tab:SetSize(65, 24)
    tab:SetID(tabIndex)
    tab.pageName = pageName

    -- Background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(unpack(COLORS.bgDark))

    -- Bottom accent border
    tab.borderBottom = tab:CreateTexture(nil, "BORDER")
    tab.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    tab.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    tab.borderBottom:SetHeight(2)
    tab.borderBottom:SetColorTexture(unpack(COLORS.borderLight))

    -- Text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", 0, 1)
    tab.text:SetText(label)
    tab.text:SetTextColor(unpack(COLORS.textMuted))

    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        GB.currentPage = self.pageName
        updatePageVisibility()
    end)

    tab:SetScript("OnEnter", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(unpack(COLORS.tabHover))
            self.text:SetTextColor(unpack(COLORS.guildGreen))
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(unpack(COLORS.bgDark))
            self.text:SetTextColor(unpack(COLORS.textMuted))
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
    GB.pageTabs[1]:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 8, -28)

    -- Create Status tab next to Chat
    GB.pageTabs[2] = createPageTab(GB.mainFrame, "Status", 2, "status")
    GB.pageTabs[2]:SetPoint("LEFT", GB.pageTabs[1], "RIGHT", 2, 0)

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

    -- Update page tab selection
    updatePageTabSelection()

    -- Adjust scroll frame and scrollbar position
    if GB.scrollFrame then
        local titleBarHeight = 26
        local pageTabHeight = 28
        local scrollTopOffset
        if GB.currentPage == "chat" then
            -- Calculate guild tab rows
            local tabWidth = 80
            local tabSpacing = 3
            local rowHeight = 38
            local maxWidth = GB.mainFrame:GetWidth() - 16
            -- Count: "All" tab + all known guilds
            local guildCount = 1
            for _ in pairs(GB.knownGuilds) do
                guildCount = guildCount + 1
            end
            local tabsPerRow = math.max(1, math.floor(maxWidth / (tabWidth + tabSpacing)))
            local numRows = math.ceil(guildCount / tabsPerRow)
            if numRows < 1 then numRows = 1 end
            scrollTopOffset = titleBarHeight + pageTabHeight + (numRows * rowHeight) + 6
        else
            -- Status page - just page tabs, no guild filter tabs
            scrollTopOffset = titleBarHeight + pageTabHeight + 6
        end
        GB.scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        -- Also adjust scrollbar track to match
        if GB.scrollBarTrack then
            GB.scrollBarTrack:SetPoint("TOPRIGHT", -8, -scrollTopOffset)
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

    local tabSpacing = 3
    local tabWidth = 80
    local rowHeight = 38
    local titleBarHeight = 26
    local pageTabHeight = 28
    local topRowY = -(titleBarHeight + pageTabHeight)  -- Below title bar and page tabs

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

-- Create the main bridge UI with modern styling
function GB:CreateBridgeUI()
    if self.mainFrame then
        return
    end

    -- Main frame with custom backdrop
    self.mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BackdropTemplate")
    self.mainFrame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    self.mainFrame:SetPoint("CENTER")
    self.mainFrame:SetMovable(true)
    self.mainFrame:SetResizable(true)
    self.mainFrame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 900, 700)
    self.mainFrame:EnableMouse(true)
    self.mainFrame:SetClampedToScreen(true)
    self.mainFrame:SetFrameStrata("MEDIUM")
    self.mainFrame:SetFrameLevel(100)

    -- Dark backdrop with subtle border
    self.mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    self.mainFrame:SetBackdropColor(unpack(COLORS.bgDark))
    self.mainFrame:SetBackdropBorderColor(unpack(COLORS.border))

    -- Title bar background - subtle gradient feel
    local titleBar = self.mainFrame:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:SetColorTexture(unpack(COLORS.bgMedium))
    self.mainFrame.titleBar = titleBar

    -- Title bar bottom border - guild green accent
    local titleBorder = self.mainFrame:CreateTexture(nil, "ARTWORK")
    titleBorder:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleBorder:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleBorder:SetHeight(1)
    titleBorder:SetColorTexture(COLORS.guildGreenDark[1], COLORS.guildGreenDark[2], COLORS.guildGreenDark[3], 0.5)

    -- Make title bar draggable
    self.mainFrame:RegisterForDrag("LeftButton")
    self.mainFrame:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    self.mainFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        GB:SaveWindowPosition()
    end)

    -- Horde logo icon
    local hordeIcon = self.mainFrame:CreateTexture(nil, "OVERLAY")
    hordeIcon:SetSize(18, 18)
    hordeIcon:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    hordeIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Horde")
    hordeIcon:SetTexCoord(0, 1, 0, 1)

    -- Title text - guild green
    self.mainFrame.title = self.mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.mainFrame.title:SetPoint("LEFT", hordeIcon, "RIGHT", 6, 0)
    self.mainFrame.title:SetText("Guild Bridge")
    self.mainFrame.title:SetTextColor(unpack(COLORS.guildGreen))

    -- Close button (X styled)
    local closeBtn = CreateFrame("Button", nil, self.mainFrame)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -5)

    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtn.text:SetPoint("CENTER", 0, 0)
    closeBtn.text:SetText("X")
    closeBtn.text:SetTextColor(unpack(COLORS.textMuted))

    closeBtn:SetScript("OnClick", function()
        GB.mainFrame:Hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 0.4, 0.4)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(COLORS.textMuted))
    end)

    -- Resize grip (bottom-right corner) - larger hit area for easier clicking
    local resizeGrip = CreateFrame("Button", nil, self.mainFrame)
    resizeGrip:SetSize(24, 24)
    resizeGrip:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6, 0.8)
    resizeGrip:GetHighlightTexture():SetVertexColor(0.8, 0.8, 0.8, 1)
    resizeGrip:SetScript("OnMouseDown", function()
        GB.mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        GB.mainFrame:StopMovingOrSizing()
        GB:SaveWindowPosition()
        GB:RebuildTabs()  -- Recalculate tab layout
    end)
    self.mainFrame.resizeGrip = resizeGrip

    -- Handle resize events
    self.mainFrame:SetScript("OnSizeChanged", function(frame, width, height)
        -- Update scroll frame bottom anchor
        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
        end
    end)

    -- Create page tabs
    createPageTabs()

    -- Build guild filter tabs
    self:RebuildTabs()

    -- Mute checkbox - subtle, in corner
    self.muteCheckbox = CreateFrame("CheckButton", nil, self.mainFrame, "UICheckButtonTemplate")
    self.muteCheckbox:SetSize(18, 18)
    self.muteCheckbox:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -26, -5)
    self.muteCheckbox.text = self.muteCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    self.muteCheckbox.text:SetPoint("RIGHT", self.muteCheckbox, "LEFT", -2, 0)
    self.muteCheckbox.text:SetText("Mute")
    self.muteCheckbox.text:SetTextColor(unpack(COLORS.textMuted))
    self.muteCheckbox:SetChecked(GuildBridgeDB.muteSend or false)
    self.muteCheckbox:SetScript("OnClick", function(checkbox)
        GuildBridgeDB.muteSend = checkbox:GetChecked()
    end)
    self.muteCheckbox:SetScript("OnEnter", function()
        GameTooltip:SetOwner(GB.muteCheckbox, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Mute outgoing bridge messages from you")
        GameTooltip:Show()
    end)
    self.muteCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Scroll frame for messages - chat area (leave room for scrollbar on right)
    self.scrollFrame = CreateFrame("ScrollingMessageFrame", nil, self.mainFrame)
    self.scrollFrame:SetPoint("TOPLEFT", 10, -94)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", -24, 40)  -- Extra space for scrollbar
    self.scrollFrame:SetFontObject(ChatFontNormal)
    self.scrollFrame:SetJustifyH("LEFT")
    self.scrollFrame:SetFading(false)
    self.scrollFrame:SetMaxLines(500)
    self.scrollFrame:EnableMouseWheel(true)
    self.scrollFrame:SetHyperlinksEnabled(true)
    self.scrollFrame:SetIndentedWordWrap(true)
    self.scrollFrame:SetSpacing(2)  -- Line spacing for readability

    -- Chat area background - very subtle
    local scrollBg = self.scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(unpack(COLORS.bgChat))

    -- Scrollbar track (visual background)
    local scrollBarTrack = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    scrollBarTrack:SetPoint("TOPRIGHT", -8, -94)
    scrollBarTrack:SetPoint("BOTTOMRIGHT", -8, 40)
    scrollBarTrack:SetWidth(12)
    scrollBarTrack:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollBarTrack:SetBackdropColor(0.05, 0.05, 0.06, 0.8)
    scrollBarTrack:SetBackdropBorderColor(unpack(COLORS.borderLight))

    -- Scrollbar slider (actual interactive element)
    local scrollBar = CreateFrame("Slider", nil, scrollBarTrack)
    scrollBar:SetPoint("TOPLEFT", 1, -1)
    scrollBar:SetPoint("BOTTOMRIGHT", -1, 1)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(1)  -- Start at bottom (newest messages)
    scrollBar:SetValueStep(1)
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetObeyStepOnDrag(true)
    self.scrollBar = scrollBar
    self.scrollBarTrack = scrollBarTrack

    -- Scrollbar thumb texture
    local thumbTexture = scrollBar:CreateTexture(nil, "OVERLAY")
    thumbTexture:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.7)
    thumbTexture:SetSize(10, 30)
    scrollBar:SetThumbTexture(thumbTexture)

    -- Track if we're programmatically updating the scrollbar (to avoid feedback loop)
    local updatingScrollBar = false

    -- Update scrollbar to reflect current scroll position
    -- ScrollingMessageFrame: offset 0 = viewing bottom (newest), higher offset = viewing older (top)
    -- Slider: value 0 = thumb at top (oldest), value max = thumb at bottom (newest)
    -- So we need to INVERT: sliderValue = maxOffset - scrollOffset
    local function updateScrollBar()
        local numMessages = self.scrollFrame:GetNumMessages()
        local maxOffset = math.max(0, numMessages - 1)

        if numMessages <= 1 then
            scrollBarTrack:Hide()
            return
        end

        local currentOffset = self.scrollFrame:GetScrollOffset()

        updatingScrollBar = true
        scrollBar:SetMinMaxValues(0, maxOffset)
        -- Invert: when offset is 0 (bottom/newest), slider should be at max (thumb at bottom)
        -- When offset is max (top/oldest), slider should be at 0 (thumb at top)
        scrollBar:SetValue(maxOffset - currentOffset)
        updatingScrollBar = false
        scrollBarTrack:Show()
    end
    self.updateScrollBar = updateScrollBar

    -- Scrollbar dragged by user - convert slider value back to scroll offset
    scrollBar:SetScript("OnValueChanged", function(bar, value)
        if updatingScrollBar then return end
        local min, max = bar:GetMinMaxValues()
        -- Invert: slider value 0 = oldest (max offset), slider value max = newest (offset 0)
        local newOffset = math.floor(max - value + 0.5)
        self.scrollFrame:SetScrollOffset(newOffset)
    end)

    -- Mouse wheel on scrollbar
    scrollBar:SetScript("OnMouseWheel", function(bar, delta)
        local min, max = bar:GetMinMaxValues()
        local val = bar:GetValue()
        -- Wheel up = show older messages = decrease slider value (thumb moves up)
        -- Wheel down = show newer messages = increase slider value (thumb moves down)
        if delta > 0 then
            bar:SetValue(math.max(min, val - 3))
        else
            bar:SetValue(math.min(max, val + 3))
        end
    end)

    -- Mouse wheel on message area
    self.scrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        if delta > 0 then
            for i = 1, 3 do frame:ScrollUp() end
        else
            for i = 1, 3 do frame:ScrollDown() end
        end
        updateScrollBar()
    end)

    self.scrollFrame:SetScript("OnHyperlinkClick", function(frame, link, text, button)
        SetItemRef(link, text, button)
    end)

    -- Update scrollbar when frame is shown
    self.scrollFrame:HookScript("OnShow", updateScrollBar)

    -- Hook AddMessage to update scrollbar when new messages arrive
    local originalAddMessage = self.scrollFrame.AddMessage
    self.scrollFrame.AddMessage = function(frame, ...)
        originalAddMessage(frame, ...)
        -- Only update if at bottom (offset 0) to keep scroll position when reading history
        if frame:GetScrollOffset() == 0 then
            updateScrollBar()
        end
    end

    -- Input box container with guild-style border
    local inputBg = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    inputBg:SetPoint("BOTTOMLEFT", 8, 6)
    inputBg:SetPoint("BOTTOMRIGHT", -8, 6)
    inputBg:SetHeight(28)
    inputBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    inputBg:SetBackdropColor(unpack(COLORS.inputBg))
    inputBg:SetBackdropBorderColor(unpack(COLORS.inputBorder))
    self.mainFrame.inputBg = inputBg

    self.inputBox = CreateFrame("EditBox", nil, inputBg)
    self.inputBox:SetPoint("TOPLEFT", 10, -6)
    self.inputBox:SetPoint("BOTTOMRIGHT", -10, 6)
    self.inputBox:SetAutoFocus(false)
    self.inputBox:SetFontObject(ChatFontNormal)
    self.inputBox:SetTextColor(unpack(COLORS.textNormal))

    self.inputBox:SetScript("OnEnterPressed", function(inputBox)
        local text = inputBox:GetText()
        if text and text ~= "" then
            GB:SendFromUI(text)
            inputBox:SetText("")
        end
    end)

    self.inputBox:SetScript("OnEscapePressed", function(inputBox)
        inputBox:ClearFocus()
    end)

    -- Focus highlight - guild green
    self.inputBox:SetScript("OnEditFocusGained", function()
        inputBg:SetBackdropBorderColor(COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3], 0.7)
    end)
    self.inputBox:SetScript("OnEditFocusLost", function()
        inputBg:SetBackdropBorderColor(unpack(COLORS.inputBorder))
    end)

    -- Restore saved position and size
    self:RestoreWindowPosition()

    -- Start hidden
    self.mainFrame:Hide()

    -- Save position when hiding
    self.mainFrame:SetScript("OnHide", function()
        GB:SaveWindowPosition()
    end)
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
