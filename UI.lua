-- MNet UI Module
-- Handles all UI elements including main frame, tabs, and dialogs

local addonName, GB = ...

-- UI Constants
local MIN_WIDTH = 380
local MIN_HEIGHT = 280
local DEFAULT_WIDTH = 600  -- Wider to accommodate roster panel
local DEFAULT_HEIGHT = 380
local DEFAULT_ROSTER_WIDTH = 140   -- Default width of roster panel
local MIN_ROSTER_WIDTH = 80        -- Minimum roster width
local MAX_ROSTER_WIDTH = 250       -- Maximum roster width
local ROSTER_WIDTH = DEFAULT_ROSTER_WIDTH  -- Current roster width (will be updated from saved vars)

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
local copyTextDialog

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

    -- Also refresh roster when connection status changes
    self:RefreshRoster()
end

-- Helper to convert hex color to RGB values (0-1)
local function hexToRGB(hex)
    if not hex or #hex ~= 6 then return 1, 1, 1 end
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

-- Refresh roster panel with connected users and synced guild members
function GB:RefreshRoster()
    if not self.rosterContent or not self.rosterPanel then return end

    -- Only show roster on chat page
    if self.currentPage ~= "chat" then
        self.rosterPanel:Hide()
        return
    end
    self.rosterPanel:Show()

    -- Hide all existing entries
    for _, entry in ipairs(self.rosterEntries) do
        entry:Hide()
    end

    -- Gather all members to display
    local members = {}
    local seenMembers = {}  -- Track by "name-realm" to avoid duplicates
    local now = GetTime()

    -- Get my own guild info for comparison
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

    -- Helper to add member if not duplicate
    local function addMember(member)
        local key = (member.name or "?") .. "-" .. (member.realm or "")
        if not seenMembers[key] then
            seenMembers[key] = true
            table.insert(members, member)
        end
    end

    -- Add members from synced rosters (these are the full guild rosters)
    for filterKey, roster in pairs(self.guildRosters or {}) do
        if roster.members then
            local guildInfo = self.knownGuilds[filterKey]
            local guildName = guildInfo and guildInfo.guildName or "Unknown"
            local guildHomeRealm = guildInfo and guildInfo.guildHomeRealm or nil

            for name, info in pairs(roster.members) do
                -- Determine realm for display
                local displayRealm = info.realm or guildHomeRealm

                addMember({
                    name = name,
                    realm = displayRealm,
                    guildName = guildName,
                    guildHomeRealm = guildHomeRealm,
                    filterKey = filterKey,
                    class = info.class,
                    isRemote = true,
                })
            end
        end
    end

    -- Add myself if in an allowed guild (mark as "me" for special display)
    if myGuildName and self.allowedGuilds[myGuildName] then
        local playerName = UnitName("player")
        local playerRealm = GetRealmName()
        local _, _, _, _, _, _, _, _, _, _, playerClass = GetPlayerInfoByGUID(UnitGUID("player"))

        -- Check if already added from roster sync, update with isMe flag
        local key = playerName .. "-" .. (playerRealm or "")
        if seenMembers[key] then
            -- Find and update
            for _, m in ipairs(members) do
                if m.name == playerName and (m.realm == playerRealm or m.realm == nil) then
                    m.isMe = true
                    m.class = playerClass
                    break
                end
            end
        else
            addMember({
                name = playerName,
                realm = playerRealm,
                guildName = myGuildName,
                guildHomeRealm = myGuildHomeRealm,
                filterKey = myFilterKey,
                class = playerClass,
                isMe = true,
            })
        end
    end

    -- Also mark connected bridge users (they have direct connection)
    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if now - info.lastSeen < 300 then
            local name = info.characterName
            local realm = info.characterRealm or info.realmName
            if name then
                local key = name .. "-" .. (realm or "")
                -- Find and mark as bridge user
                for _, m in ipairs(members) do
                    local mKey = m.name .. "-" .. (m.realm or "")
                    if mKey == key then
                        m.isBNet = true
                        break
                    end
                end
            end
        end
    end

    -- Mark whisper alts
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 90 then
            local name, realm = strsplit("-", altName)
            if name then
                -- Find and mark as whisper alt
                for _, m in ipairs(members) do
                    if m.name == name and (m.realm == realm or (not m.realm and not realm)) then
                        m.isWhisper = true
                        break
                    end
                end
            end
        end
    end

    -- Filter by current tab selection
    local filteredMembers = {}
    for _, member in ipairs(members) do
        if self.currentFilter == nil then
            -- "All" tab - show everyone
            table.insert(filteredMembers, member)
        elseif member.filterKey == self.currentFilter then
            -- Specific guild tab - only show members from that guild
            table.insert(filteredMembers, member)
        end
    end

    -- Sort members: myself first, then alphabetically
    table.sort(filteredMembers, function(a, b)
        if a.isMe then return true end
        if b.isMe then return false end
        return (a.name or "") < (b.name or "")
    end)

    -- Update header with count
    local headerText = "Online (" .. #filteredMembers .. ")"
    self.rosterHeader:SetText(headerText)

    -- Create/reuse entry frames
    local yOffset = 0
    local entryHeight = 16
    local partyIconSize = 12
    for i, member in ipairs(filteredMembers) do
        local entry = self.rosterEntries[i]
        if not entry then
            -- Create new entry frame
            entry = CreateFrame("Frame", nil, self.rosterContent)
            entry:SetSize(ROSTER_WIDTH - 30, entryHeight)

            -- Party icon (small group icon on the left)
            entry.partyIcon = entry:CreateTexture(nil, "OVERLAY")
            entry.partyIcon:SetSize(partyIconSize, partyIconSize)
            entry.partyIcon:SetPoint("LEFT", 1, 0)
            entry.partyIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            entry.partyIcon:SetVertexColor(0.4, 0.8, 1.0, 1)  -- Light blue tint
            entry.partyIcon:Hide()

            -- Name text (offset to accommodate party icon when shown)
            entry.nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
            entry.nameText:SetPoint("LEFT", 2, 0)
            entry.nameText:SetJustifyH("LEFT")
            entry.nameText:SetWidth(ROSTER_WIDTH - 34)
            entry.nameText:SetWordWrap(false)

            -- Hover highlight
            entry.highlight = entry:CreateTexture(nil, "BACKGROUND")
            entry.highlight:SetAllPoints()
            entry.highlight:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.3)
            entry.highlight:Hide()

            entry:EnableMouse(true)
            entry:SetScript("OnEnter", function(self)
                self.highlight:Show()
                -- Show tooltip with connection info
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                local tooltipName = self.memberData.name or "Unknown"
                if self.memberData.realm then
                    tooltipName = tooltipName .. "-" .. self.memberData.realm
                end
                GameTooltip:SetText(tooltipName, 1, 1, 1)
                if self.memberData.isMe then
                    GameTooltip:AddLine("(You)", 0.7, 0.7, 0.7)
                elseif self.memberData.isBNet then
                    GameTooltip:AddLine("(BNet Friend)", 0.5, 0.8, 1)
                elseif self.memberData.isWhisper then
                    GameTooltip:AddLine("(Same Account)", 0.8, 0.6, 1)
                end
                if self.memberData.inParty then
                    GameTooltip:AddLine("In Party", 0.4, 0.8, 1.0)
                end
                GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            entry:SetScript("OnLeave", function(self)
                self.highlight:Hide()
                GameTooltip:Hide()
            end)

            -- Right-click to show context menu
            entry:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    GB:ShowRosterContextMenu(self.memberData)
                end
            end)

            self.rosterEntries[i] = entry
        end

        -- Update entry data
        entry.memberData = member
        entry:SetPoint("TOPLEFT", 0, -yOffset)

        -- Check if member is in a party (local or remote)
        local inParty = self:IsInMyParty(member.name, member.realm) or self:IsInAnyParty(member.name, member.realm)
        member.inParty = inParty

        -- Show/hide party icon and adjust name text position
        if inParty then
            entry.partyIcon:Show()
            entry.nameText:SetPoint("LEFT", partyIconSize + 2, 0)
            entry.nameText:SetWidth(ROSTER_WIDTH - 34 - partyIconSize)
        else
            entry.partyIcon:Hide()
            entry.nameText:SetPoint("LEFT", 2, 0)
            entry.nameText:SetWidth(ROSTER_WIDTH - 34)
        end

        -- Format display name with realm (like native guild roster)
        local displayName = member.name or "Unknown"
        if member.realm and member.realm ~= "" then
            displayName = displayName .. "-" .. member.realm
        end
        if member.isMe then
            displayName = displayName .. " *"
        end

        -- Get class color
        local r, g, b = 1, 1, 1  -- Default white
        if member.class and GB.classColors[member.class] then
            r, g, b = hexToRGB(GB.classColors[member.class])
        elseif member.isMe then
            r, g, b = COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3]
        end

        entry.nameText:SetText(displayName)
        entry.nameText:SetTextColor(r, g, b, 1)

        entry:Show()
        yOffset = yOffset + entryHeight
    end

    -- Update content height for scrolling
    self.rosterContent:SetHeight(math.max(1, yOffset))

    -- Update scrollbar to reflect new content size
    if self.updateRosterScrollBar then
        self.updateRosterScrollBar()
    end
end

-- Show roster context menu for a member using WoW's native player dropdown
function GB:ShowRosterContextMenu(memberData)
    if not memberData or memberData.isMe then return end

    -- Build the full name (Name-Realm format for cross-realm)
    local fullName = memberData.name
    if memberData.realm and memberData.realm ~= "" then
        fullName = memberData.name .. "-" .. memberData.realm
    end

    -- Use WoW's native player context menu
    -- This opens the same dropdown you see when right-clicking a name in chat
    if Menu and Menu.GetManager then
        -- Dragonflight+ menu system
        MenuUtil.CreateContextMenu(nil, function(owner, rootDescription)
            rootDescription:CreateTitle(fullName)
            rootDescription:CreateButton("Whisper", function()
                ChatFrame_OpenChat("/w " .. fullName .. " ")
            end)
            rootDescription:CreateButton("Invite", function()
                C_PartyInfo.InviteUnit(fullName)
            end)
            rootDescription:CreateButton("Ignore", function()
                AddIgnore(fullName)
            end)
            rootDescription:CreateButton("Report Player", function()
                PlayerReportFrame:InitiateReport(Enum.ReportType.Chat, fullName)
            end)
            rootDescription:CreateButton("Copy Name", function()
                -- Put name in chat editbox for easy copying
                local editBox = ChatFrame1EditBox
                if editBox then
                    editBox:SetText(fullName)
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:HighlightText()
                end
            end)
            rootDescription:CreateButton(CANCEL, function() end)
        end)
    else
        -- Fallback: use SetItemRef with RightButton (may not work in all versions)
        SetItemRef("player:" .. fullName, "|Hplayer:" .. fullName .. "|h[" .. fullName .. "]|h", "RightButton")
    end
end

-- Forget a guild from known guilds
local function forgetGuild(filterKey)
    if not filterKey then return end
    GB.knownGuilds[filterKey] = nil
    MNetDB.knownGuilds = GB.knownGuilds
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
        MNetDB.knownGuilds = GB.knownGuilds
        GB:RebuildTabs()
    end
end

-- Show realm input dialog
showRealmInputDialog = function(filterKey, guildName)
    if not realmInputDialog then
        realmInputDialog = CreateFrame("Frame", "MNetRealmDialog", UIParent, "BackdropTemplate")
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

    contextMenu = CreateFrame("Frame", "MNetContextMenu", UIParent, "BackdropTemplate")
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
    MNetDB.knownGuilds = GB.knownGuilds

    -- Reset filter if needed
    GB.currentFilter = nil
    GB:RebuildTabs()
    GB:RefreshMessages()
end

-- Ensure All tab context menu is created
local function ensureAllTabContextMenu()
    if allTabContextMenu then return end

    allTabContextMenu = CreateFrame("Frame", "MNetAllTabContextMenu", UIParent, "BackdropTemplate")
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

-- Strip WoW color codes and hyperlinks from text
local function stripColorCodes(text)
    if not text then return "" end
    -- Remove hyperlinks but keep the visible text: |Htype:data|h[visible]|h -> [visible]
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    -- Remove color codes: |cffXXXXXX -> empty, |r -> empty
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    -- Remove any remaining pipe escapes
    text = text:gsub("||", "|")
    return text
end

-- Show copy text dialog
local function showCopyTextDialog(text)
    if not copyTextDialog then
        copyTextDialog = CreateFrame("Frame", "MNetCopyDialog", UIParent, "BackdropTemplate")
        copyTextDialog:SetSize(400, 120)
        copyTextDialog:SetPoint("CENTER")
        copyTextDialog:SetFrameStrata("DIALOG")
        copyTextDialog:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        copyTextDialog:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        copyTextDialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        copyTextDialog:EnableMouse(true)
        copyTextDialog:SetMovable(true)
        copyTextDialog:RegisterForDrag("LeftButton")
        copyTextDialog:SetScript("OnDragStart", copyTextDialog.StartMoving)
        copyTextDialog:SetScript("OnDragStop", copyTextDialog.StopMovingOrSizing)

        copyTextDialog.title = copyTextDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        copyTextDialog.title:SetPoint("TOP", 0, -10)
        copyTextDialog.title:SetText("Copy Text (Ctrl+C)")
        copyTextDialog.title:SetTextColor(COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3])

        -- Scrollable edit box for longer messages
        local scrollFrame = CreateFrame("ScrollFrame", nil, copyTextDialog, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -30)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

        copyTextDialog.editBox = CreateFrame("EditBox", nil, scrollFrame)
        copyTextDialog.editBox:SetMultiLine(true)
        copyTextDialog.editBox:SetFontObject(ChatFontNormal)
        copyTextDialog.editBox:SetWidth(350)
        copyTextDialog.editBox:SetAutoFocus(true)
        copyTextDialog.editBox:SetTextColor(unpack(COLORS.textNormal))
        scrollFrame:SetScrollChild(copyTextDialog.editBox)

        copyTextDialog.closeButton = CreateFrame("Button", nil, copyTextDialog, "UIPanelButtonTemplate")
        copyTextDialog.closeButton:SetSize(80, 22)
        copyTextDialog.closeButton:SetPoint("BOTTOM", 0, 10)
        copyTextDialog.closeButton:SetText("Close")
        copyTextDialog.closeButton:SetScript("OnClick", function()
            copyTextDialog:Hide()
        end)

        copyTextDialog.editBox:SetScript("OnEscapePressed", function()
            copyTextDialog:Hide()
        end)

        copyTextDialog:Hide()
    end

    -- Strip color codes and set text
    local cleanText = stripColorCodes(text)
    copyTextDialog.editBox:SetText(cleanText)
    copyTextDialog:Show()
    copyTextDialog.editBox:HighlightText()
    copyTextDialog.editBox:SetFocus()
end

-- Export for use elsewhere
GB.ShowCopyTextDialog = showCopyTextDialog

-- Copy chat context menu
local copyChatMenu

local function ensureCopyChatMenu()
    if copyChatMenu then return end

    copyChatMenu = CreateFrame("Frame", "MNetCopyChatMenu", UIParent, "BackdropTemplate")
    copyChatMenu:SetSize(130, 72)
    copyChatMenu:SetFrameStrata("DIALOG")
    copyChatMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    copyChatMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    copyChatMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    copyChatMenu:Hide()

    -- Copy All button
    local copyAllButton = CreateFrame("Button", nil, copyChatMenu)
    copyAllButton:SetSize(120, 20)
    copyAllButton:SetPoint("TOP", copyChatMenu, "TOP", 0, -8)
    copyAllButton.text = copyAllButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyAllButton.text:SetPoint("CENTER")
    copyAllButton.text:SetText("Copy All Messages")
    copyAllButton.text:SetTextColor(1, 0.82, 0)
    copyAllButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    copyAllButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    copyAllButton:SetScript("OnClick", function()
        copyChatMenu:Hide()
        -- Gather all visible messages based on current filter
        local lines = {}
        for _, msg in ipairs(GB.messageHistory) do
            if GB.currentFilter == nil or msg.filterKey == GB.currentFilter then
                local displayMsg = GB.currentFilter and msg.formattedNoTag or msg.formatted
                table.insert(lines, displayMsg)
            end
        end
        if #lines > 0 then
            showCopyTextDialog(table.concat(lines, "\n"))
        end
    end)

    -- Copy Last 10 button
    local copyRecentButton = CreateFrame("Button", nil, copyChatMenu)
    copyRecentButton:SetSize(120, 20)
    copyRecentButton:SetPoint("TOP", copyAllButton, "BOTTOM", 0, -2)
    copyRecentButton.text = copyRecentButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyRecentButton.text:SetPoint("CENTER")
    copyRecentButton.text:SetText("Copy Last 10")
    copyRecentButton.text:SetTextColor(1, 0.82, 0)
    copyRecentButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    copyRecentButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    copyRecentButton:SetScript("OnClick", function()
        copyChatMenu:Hide()
        -- Gather last 10 visible messages
        local lines = {}
        for i = #GB.messageHistory, 1, -1 do
            local msg = GB.messageHistory[i]
            if GB.currentFilter == nil or msg.filterKey == GB.currentFilter then
                local displayMsg = GB.currentFilter and msg.formattedNoTag or msg.formatted
                table.insert(lines, 1, displayMsg)
                if #lines >= 10 then break end
            end
        end
        if #lines > 0 then
            showCopyTextDialog(table.concat(lines, "\n"))
        end
    end)

    -- Cancel button
    local cancelButton = CreateFrame("Button", nil, copyChatMenu)
    cancelButton:SetSize(120, 20)
    cancelButton:SetPoint("TOP", copyRecentButton, "BOTTOM", 0, -2)
    cancelButton.text = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelButton.text:SetPoint("CENTER")
    cancelButton.text:SetText("Cancel")
    cancelButton.text:SetTextColor(0.7, 0.7, 0.7)
    cancelButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7)
    end)
    cancelButton:SetScript("OnClick", function()
        copyChatMenu:Hide()
    end)

    copyChatMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    copyChatMenu:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    copyChatMenu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if not MouseIsOver(self) and not (copyTextDialog and copyTextDialog:IsShown()) then
                self:Hide()
            end
        end
    end)
    copyChatMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

-- Show copy chat menu at cursor
function GB:ShowCopyChatMenu()
    ensureCopyChatMenu()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    copyChatMenu:ClearAllPoints()
    copyChatMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    copyChatMenu:Show()
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
            GB:RefreshRoster()
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

-- Update page tab selection (Chat vs Status) - segmented control style
updatePageTabSelection = function()
    for i, tab in ipairs(GB.pageTabs) do
        if tab.pageName == GB.currentPage then
            -- Selected segment - filled with guild green
            tab.bg:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.9)
            tab.text:SetTextColor(1, 1, 1, 1)
        else
            -- Unselected segment - transparent with muted text
            tab.bg:SetColorTexture(0, 0, 0, 0.3)
            tab.text:SetTextColor(unpack(COLORS.textMuted))
        end
    end
end

-- Create a styled page tab (Chat/Status) - segmented control style
createPageTab = function(parent, label, tabIndex, pageName, isFirst, isLast)
    local tab = CreateFrame("Button", "MNetPageTab" .. tabIndex, parent)
    tab:SetSize(55, 22)
    tab:SetID(tabIndex)
    tab.pageName = pageName

    -- Background (will be colored based on selection)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0, 0, 0, 0.3)

    -- Text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", 0, 0)
    tab.text:SetText(label)
    tab.text:SetTextColor(unpack(COLORS.textMuted))

    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        GB.currentPage = self.pageName
        updatePageVisibility()
    end)

    tab:SetScript("OnEnter", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.4)
            self.text:SetTextColor(unpack(COLORS.guildGreen))
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if GB.currentPage ~= self.pageName then
            self.bg:SetColorTexture(0, 0, 0, 0.3)
            self.text:SetTextColor(unpack(COLORS.textMuted))
        end
    end)

    return tab
end

-- Create page tabs (Chat and Status) as a segmented control
local function createPageTabs()
    if not GB.mainFrame then return end

    -- Clear existing page tabs
    for _, tab in pairs(GB.pageTabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    GB.pageTabs = {}

    -- Create segmented control container
    if not GB.pageTabContainer then
        GB.pageTabContainer = CreateFrame("Frame", nil, GB.mainFrame, "BackdropTemplate")
    end
    local container = GB.pageTabContainer
    container:SetSize(112, 24)  -- 55*2 + 2 padding
    container:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 8, -28)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
    container:SetBackdropBorderColor(COLORS.guildGreenDark[1], COLORS.guildGreenDark[2], COLORS.guildGreenDark[3], 0.8)
    container:Show()

    -- Create Chat tab (left segment)
    GB.pageTabs[1] = createPageTab(container, "Chat", 1, "chat", true, false)
    GB.pageTabs[1]:SetPoint("LEFT", container, "LEFT", 1, 0)

    -- Create Status tab (right segment)
    GB.pageTabs[2] = createPageTab(container, "Status", 2, "status", false, true)
    GB.pageTabs[2]:SetPoint("LEFT", GB.pageTabs[1], "RIGHT", 0, 0)

    -- Separator line between page tabs and guild tabs
    if not GB.tabSeparator then
        GB.tabSeparator = GB.mainFrame:CreateTexture(nil, "ARTWORK")
    end
    GB.tabSeparator:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 8, -56)
    GB.tabSeparator:SetPoint("TOPRIGHT", GB.mainFrame, "TOPRIGHT", -8, -56)
    GB.tabSeparator:SetHeight(1)
    GB.tabSeparator:SetColorTexture(COLORS.borderLight[1], COLORS.borderLight[2], COLORS.borderLight[3], 0.5)

    updatePageTabSelection()
end

-- Update page visibility (show/hide elements based on current page)
updatePageVisibility = function()
    if not GB.mainFrame then return end

    -- Hide/show guild filter tabs and separator based on current page
    for key, tab in pairs(GB.tabButtons) do
        if key:match("^guild") or key == "all" then
            if GB.currentPage == "chat" then
                tab:Show()
            else
                tab:Hide()
            end
        end
    end

    -- Show/hide separator line
    if GB.tabSeparator then
        if GB.currentPage == "chat" then
            GB.tabSeparator:Show()
        else
            GB.tabSeparator:Hide()
        end
    end

    -- Update page tab selection
    updatePageTabSelection()

    -- Adjust scroll frame and scrollbar position
    if GB.scrollFrame then
        local titleBarHeight = 26
        local pageTabHeight = 32  -- Segmented control + spacing
        local separatorHeight = 4  -- Separator + padding
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
            scrollTopOffset = titleBarHeight + pageTabHeight + separatorHeight + (numRows * rowHeight) + 4
        else
            -- Status page - just page tabs, no guild filter tabs
            scrollTopOffset = titleBarHeight + pageTabHeight + 8
        end
        GB.scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        -- Also adjust scrollbar track to match (left of roster panel)
        if GB.scrollBarTrack then
            GB.scrollBarTrack:SetPoint("TOPRIGHT", -(ROSTER_WIDTH + 10), -scrollTopOffset)
        end
        -- Also adjust roster panel position
        if GB.rosterPanel then
            GB.rosterPanel:SetPoint("TOPRIGHT", -8, -scrollTopOffset)
        end
    end

    GB:RefreshMessages()
    GB:RefreshRoster()
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
    local pageTabHeight = 32  -- Segmented control height + spacing
    local separatorHeight = 4  -- Separator line + padding
    local topRowY = -(titleBarHeight + pageTabHeight + separatorHeight)  -- Below title bar, page tabs, and separator

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
    self.mainFrame = CreateFrame("Frame", "MNetFrame", UIParent, "BackdropTemplate")
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
    self.mainFrame.title:SetText("MNet")
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
    local resizeGrip = CreateFrame("Frame", nil, self.mainFrame)
    resizeGrip:SetSize(24, 24)
    resizeGrip:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeGrip:EnableMouse(true)

    -- Visual textures
    local gripTexture = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTexture:SetVertexColor(0.6, 0.6, 0.6, 0.8)
    resizeGrip.texture = gripTexture

    resizeGrip:SetScript("OnEnter", function(self)
        self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        self.texture:SetVertexColor(0.8, 0.8, 0.8, 1)
    end)
    resizeGrip:SetScript("OnLeave", function(self)
        self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        self.texture:SetVertexColor(0.6, 0.6, 0.6, 0.8)
    end)

    -- Use drag for resizing - only triggers when actually dragging, not on click
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        GB.mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", function()
        GB.mainFrame:StopMovingOrSizing()
        GB:SaveWindowPosition()
        GB:RebuildTabs()
    end)
    self.mainFrame.resizeGrip = resizeGrip

    -- Handle resize events
    self.mainFrame:SetScript("OnSizeChanged", function(frame, width, height)
        -- Update scroll frame bottom anchor (account for roster panel)
        local currentRosterWidth = GB.rosterWidth or ROSTER_WIDTH
        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(currentRosterWidth + 24), 40)
        end
    end)

    -- Create page tabs (segmented control)
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
    self.muteCheckbox:SetChecked(MNetDB.muteSend or false)
    self.muteCheckbox:SetScript("OnClick", function(checkbox)
        MNetDB.muteSend = checkbox:GetChecked()
    end)
    self.muteCheckbox:SetScript("OnEnter", function()
        GameTooltip:SetOwner(GB.muteCheckbox, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Mute bridge messages")
        GameTooltip:AddLine("Prevents outgoing messages and hides", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("incoming bridge messages from native chat", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    self.muteCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Scroll frame container for messages - chat area (leave room for scrollbar and roster on right)
    -- Using ScrollFrame + EditBox to allow text selection with Ctrl+C
    local chatScrollFrame = CreateFrame("ScrollFrame", nil, self.mainFrame)
    chatScrollFrame:SetPoint("TOPLEFT", 10, -100)  -- Adjusted for new layout
    chatScrollFrame:SetPoint("BOTTOMRIGHT", -(ROSTER_WIDTH + 24), 40)  -- Room for scrollbar + roster

    -- Chat area background - very subtle
    local scrollBg = chatScrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(unpack(COLORS.bgChat))

    -- EditBox for selectable text (non-editable)
    local chatEditBox = CreateFrame("EditBox", nil, chatScrollFrame)
    chatEditBox:SetMultiLine(true)
    chatEditBox:SetAutoFocus(false)
    chatEditBox:SetFontObject(ChatFontNormal)
    chatEditBox:SetTextColor(unpack(COLORS.textNormal))
    chatEditBox:SetWidth(chatScrollFrame:GetWidth() or 300)
    chatEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    chatEditBox:EnableMouse(true)
    chatEditBox:SetHyperlinksEnabled(true)

    -- Make it look like it's not editable but allow selection
    chatEditBox:SetScript("OnChar", function(self) end)  -- Ignore typed characters
    chatEditBox:SetScript("OnKeyDown", function(self, key)
        -- Allow Ctrl+C and Ctrl+A, block everything else that would modify text
        if IsControlKeyDown() and (key == "C" or key == "A") then
            return  -- Allow copy and select all
        end
        -- Block text-modifying keys
        if key == "BACKSPACE" or key == "DELETE" or key == "ENTER" then
            return
        end
    end)

    -- Prevent text modification but allow selection
    chatEditBox:SetScript("OnTextChanged", function(self)
        -- If text was modified (not by us), restore it
        if self.expectedText and self:GetText() ~= self.expectedText then
            self:SetText(self.expectedText)
        end
    end)

    chatScrollFrame:SetScrollChild(chatEditBox)
    self.chatScrollFrame = chatScrollFrame
    self.chatEditBox = chatEditBox

    -- Clear selection when clicking outside the EditBox
    -- Listen for global mouse clicks and clear focus if click is outside
    local clickCatcher = CreateFrame("Frame", nil, UIParent)
    clickCatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
    clickCatcher:SetScript("OnEvent", function(frame, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            -- Check if mouse is over the chat EditBox
            if chatEditBox:HasFocus() and not MouseIsOver(chatEditBox) and not MouseIsOver(chatScrollFrame) then
                chatEditBox:ClearFocus()
                chatEditBox:HighlightText(0, 0)  -- Clear selection
            end
        end
    end)

    -- Create a compatibility layer so existing code using scrollFrame still works
    -- This wraps the new EditBox-based system to mimic ScrollingMessageFrame API
    self.scrollFrame = {
        _editBox = chatEditBox,
        _scrollFrame = chatScrollFrame,
        _messages = {},
        _maxLines = 500,

        AddMessage = function(self, msg)
            table.insert(self._messages, msg)
            -- Trim to max lines
            while #self._messages > self._maxLines do
                table.remove(self._messages, 1)
            end
            -- Rebuild text
            local fullText = table.concat(self._messages, "\n")
            self._editBox.expectedText = fullText
            self._editBox:SetText(fullText)
            -- Auto-scroll to bottom and update scrollbar
            C_Timer.After(0.01, function()
                local scrollMax = self._scrollFrame:GetVerticalScrollRange()
                self._scrollFrame:SetVerticalScroll(scrollMax)
                -- Update the scrollbar if available
                if GB.updateScrollBar then
                    GB.updateScrollBar()
                end
            end)
        end,

        Clear = function(self)
            self._messages = {}
            self._editBox.expectedText = ""
            self._editBox:SetText("")
        end,

        GetNumMessages = function(self)
            return #self._messages
        end,

        SetScrollOffset = function(self, offset)
            -- Convert offset (lines from bottom) to scroll position
            local scrollMax = self._scrollFrame:GetVerticalScrollRange()
            local _, fontHeight = self._editBox:GetFont()
            local lineHeight = fontHeight or 14
            local scrollPos = scrollMax - (offset * lineHeight)
            self._scrollFrame:SetVerticalScroll(math.max(0, scrollPos))
        end,

        GetScrollOffset = function(self)
            local scrollMax = self._scrollFrame:GetVerticalScrollRange()
            local currentScroll = self._scrollFrame:GetVerticalScroll()
            local _, fontHeight = self._editBox:GetFont()
            local lineHeight = fontHeight or 14
            return math.floor((scrollMax - currentScroll) / lineHeight)
        end,

        ScrollUp = function(self)
            local current = self._scrollFrame:GetVerticalScroll()
            local _, fontHeight = self._editBox:GetFont()
            local lineHeight = fontHeight or 14
            self._scrollFrame:SetVerticalScroll(math.max(0, current - lineHeight))
        end,

        ScrollDown = function(self)
            local current = self._scrollFrame:GetVerticalScroll()
            local scrollMax = self._scrollFrame:GetVerticalScrollRange()
            local _, fontHeight = self._editBox:GetFont()
            local lineHeight = fontHeight or 14
            self._scrollFrame:SetVerticalScroll(math.min(scrollMax, current + lineHeight))
        end,

        ScrollToBottom = function(self)
            local scrollMax = self._scrollFrame:GetVerticalScrollRange()
            self._scrollFrame:SetVerticalScroll(scrollMax)
        end,

        GetHeight = function(self)
            return self._scrollFrame:GetHeight()
        end,

        GetFontObject = function(self)
            return self._editBox:GetFontObject()
        end,

        GetSpacing = function(self)
            return 0  -- EditBox doesn't have spacing like ScrollingMessageFrame
        end,

        SetPoint = function(self, ...)
            self._scrollFrame:SetPoint(...)
        end,

        Show = function(self)
            self._scrollFrame:Show()
        end,

        Hide = function(self)
            self._scrollFrame:Hide()
        end,

        IsVisible = function(self)
            return self._scrollFrame:IsVisible()
        end,

        HookScript = function(self, event, handler)
            self._scrollFrame:HookScript(event, handler)
        end,

        SetScript = function(self, event, handler)
            if event == "OnMouseWheel" then
                self._scrollFrame:EnableMouseWheel(true)
                self._scrollFrame:SetScript(event, handler)
            elseif event == "OnHyperlinkClick" then
                self._editBox:SetScript(event, handler)
            elseif event == "OnMouseUp" then
                self._scrollFrame:SetScript(event, handler)
            else
                self._scrollFrame:SetScript(event, handler)
            end
        end,
    }

    -- Scrollbar track (visual background) - positioned to left of roster panel
    local scrollBarTrack = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    scrollBarTrack:SetPoint("TOPRIGHT", -(ROSTER_WIDTH + 10), -100)  -- Left of roster panel
    scrollBarTrack:SetPoint("BOTTOMRIGHT", -(ROSTER_WIDTH + 10), 40)
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

    -- Update scrollbar to reflect current scroll position for EditBox-based scrolling
    local function updateScrollBar()
        local scrollMax = chatScrollFrame:GetVerticalScrollRange()

        if scrollMax <= 0 then
            -- All content fits in view, no scrolling needed
            scrollBarTrack:Hide()
            return
        end

        local currentScroll = chatScrollFrame:GetVerticalScroll()

        updatingScrollBar = true
        scrollBar:SetMinMaxValues(0, scrollMax)
        scrollBar:SetValue(currentScroll)
        updatingScrollBar = false
        scrollBarTrack:Show()
    end
    self.updateScrollBar = updateScrollBar

    -- Scrollbar dragged by user
    scrollBar:SetScript("OnValueChanged", function(bar, value)
        if updatingScrollBar then return end
        chatScrollFrame:SetVerticalScroll(value)
    end)

    -- Mouse wheel on scrollbar
    scrollBar:SetScript("OnMouseWheel", function(bar, delta)
        local current = chatScrollFrame:GetVerticalScroll()
        local scrollMax = chatScrollFrame:GetVerticalScrollRange()
        local step = 42  -- About 3 lines
        if delta > 0 then
            chatScrollFrame:SetVerticalScroll(math.max(0, current - step))
        else
            chatScrollFrame:SetVerticalScroll(math.min(scrollMax, current + step))
        end
        updateScrollBar()
    end)

    -- Mouse wheel on message area
    chatScrollFrame:EnableMouseWheel(true)
    chatScrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        local current = frame:GetVerticalScroll()
        local scrollMax = frame:GetVerticalScrollRange()
        local step = 42  -- About 3 lines
        if delta > 0 then
            frame:SetVerticalScroll(math.max(0, current - step))
        else
            frame:SetVerticalScroll(math.min(scrollMax, current + step))
        end
        updateScrollBar()
    end)

    -- Hyperlink clicks on the EditBox
    chatEditBox:SetScript("OnHyperlinkClick", function(frame, link, text, button)
        SetItemRef(link, text, button)
    end)

    -- Update scrollbar when frame is shown
    chatScrollFrame:HookScript("OnShow", updateScrollBar)

    -- Update EditBox width when scroll frame size changes
    chatScrollFrame:SetScript("OnSizeChanged", function(frame, width, height)
        chatEditBox:SetWidth(width)
        updateScrollBar()
    end)

    -- ============================================================================
    -- ROSTER PANEL (right side)
    -- Shows connected bridge users filtered by current tab
    -- ============================================================================

    -- Restore saved roster width or use default
    if self.rosterWidth then
        ROSTER_WIDTH = math.max(MIN_ROSTER_WIDTH, math.min(MAX_ROSTER_WIDTH, self.rosterWidth))
    else
        ROSTER_WIDTH = DEFAULT_ROSTER_WIDTH
        self.rosterWidth = ROSTER_WIDTH
    end

    -- Roster container frame
    local rosterPanel = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    rosterPanel:SetPoint("TOPRIGHT", -8, -100)  -- Same top as scroll frame
    rosterPanel:SetPoint("BOTTOMRIGHT", -8, 40)  -- Same bottom as scroll frame
    rosterPanel:SetWidth(ROSTER_WIDTH)
    rosterPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    rosterPanel:SetBackdropColor(0.04, 0.04, 0.05, 0.85)
    rosterPanel:SetBackdropBorderColor(unpack(COLORS.borderLight))
    self.rosterPanel = rosterPanel

    -- Roster header
    local rosterHeader = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rosterHeader:SetPoint("TOP", rosterPanel, "TOP", 0, -6)
    rosterHeader:SetText("Online")
    rosterHeader:SetTextColor(unpack(COLORS.guildGreen))
    self.rosterHeader = rosterHeader

    -- Roster scroll frame (for member list) - use basic ScrollFrame, not template
    local rosterScrollFrame = CreateFrame("ScrollFrame", nil, rosterPanel)
    rosterScrollFrame:SetPoint("TOPLEFT", 4, -22)
    rosterScrollFrame:SetPoint("BOTTOMRIGHT", -14, 4)

    -- Roster content frame (holds member entries)
    local rosterContent = CreateFrame("Frame", nil, rosterScrollFrame)
    rosterContent:SetSize(ROSTER_WIDTH - 18, 1)  -- Height will grow
    rosterScrollFrame:SetScrollChild(rosterContent)
    self.rosterContent = rosterContent
    self.rosterScrollFrame = rosterScrollFrame

    -- Custom scrollbar track (background)
    local rosterScrollTrack = CreateFrame("Frame", nil, rosterPanel, "BackdropTemplate")
    rosterScrollTrack:SetPoint("TOPRIGHT", -4, -22)
    rosterScrollTrack:SetPoint("BOTTOMRIGHT", -4, 4)
    rosterScrollTrack:SetWidth(8)
    rosterScrollTrack:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    rosterScrollTrack:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

    -- Custom scrollbar slider
    local rosterScrollBar = CreateFrame("Slider", nil, rosterScrollTrack)
    rosterScrollBar:SetPoint("TOPLEFT", 0, 0)
    rosterScrollBar:SetPoint("BOTTOMRIGHT", 0, 0)
    rosterScrollBar:SetOrientation("VERTICAL")
    rosterScrollBar:SetMinMaxValues(0, 1)
    rosterScrollBar:SetValue(0)
    rosterScrollBar:SetObeyStepOnDrag(true)
    rosterScrollBar:SetValueStep(1)

    -- Scrollbar thumb texture (will be sized proportionally)
    local rosterThumbTexture = rosterScrollBar:CreateTexture(nil, "OVERLAY")
    rosterThumbTexture:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.7)
    rosterThumbTexture:SetSize(8, 30)  -- Default size, will be updated
    rosterScrollBar:SetThumbTexture(rosterThumbTexture)

    -- Track if we're programmatically updating (avoid feedback loop)
    local updatingRosterScrollBar = false

    -- Update roster scrollbar to reflect content/viewport ratio
    local function updateRosterScrollBar()
        local contentHeight = rosterContent:GetHeight()
        local viewportHeight = rosterScrollFrame:GetHeight()

        if contentHeight <= viewportHeight or contentHeight <= 0 then
            -- All content fits, hide scrollbar
            rosterScrollTrack:Hide()
            rosterScrollFrame:SetVerticalScroll(0)
            return
        end

        rosterScrollTrack:Show()

        -- Calculate proportional thumb size
        local trackHeight = rosterScrollTrack:GetHeight()
        local thumbRatio = viewportHeight / contentHeight
        local thumbHeight = math.max(20, math.min(trackHeight, trackHeight * thumbRatio))
        rosterThumbTexture:SetHeight(thumbHeight)

        -- Calculate max scroll value
        local maxScroll = contentHeight - viewportHeight

        updatingRosterScrollBar = true
        rosterScrollBar:SetMinMaxValues(0, maxScroll)
        rosterScrollBar:SetValue(rosterScrollFrame:GetVerticalScroll())
        updatingRosterScrollBar = false
    end
    self.updateRosterScrollBar = updateRosterScrollBar

    -- When scrollbar is dragged, update scroll position
    rosterScrollBar:SetScript("OnValueChanged", function(bar, value)
        if updatingRosterScrollBar then return end
        rosterScrollFrame:SetVerticalScroll(value)
    end)

    -- Mouse wheel scrolling on roster panel
    rosterPanel:EnableMouseWheel(true)
    rosterPanel:SetScript("OnMouseWheel", function(frame, delta)
        local contentHeight = rosterContent:GetHeight()
        local viewportHeight = rosterScrollFrame:GetHeight()
        if contentHeight <= viewportHeight then return end

        local maxScroll = contentHeight - viewportHeight
        local scrollStep = 16 * 2  -- 2 entries per scroll
        local currentScroll = rosterScrollFrame:GetVerticalScroll()
        local newScroll = currentScroll - (delta * scrollStep)

        newScroll = math.max(0, math.min(maxScroll, newScroll))
        rosterScrollFrame:SetVerticalScroll(newScroll)
        updateRosterScrollBar()
    end)

    -- Also enable wheel scrolling on scroll frame itself
    rosterScrollFrame:EnableMouseWheel(true)
    rosterScrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        rosterPanel:GetScript("OnMouseWheel")(rosterPanel, delta)
    end)

    -- Store roster entry frames for reuse
    self.rosterEntries = {}

    -- ============================================================================
    -- ROSTER RESIZE HANDLE (left edge of roster panel)
    -- ============================================================================

    local rosterResizeHandle = CreateFrame("Frame", nil, rosterPanel)
    rosterResizeHandle:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 0, 0)
    rosterResizeHandle:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 0, 0)
    rosterResizeHandle:SetWidth(6)
    rosterResizeHandle:EnableMouse(true)

    -- Visual indicator (subtle line)
    local resizeIndicator = rosterResizeHandle:CreateTexture(nil, "OVERLAY")
    resizeIndicator:SetPoint("LEFT", 1, 0)
    resizeIndicator:SetSize(2, 0)
    resizeIndicator:SetPoint("TOP", 0, -4)
    resizeIndicator:SetPoint("BOTTOM", 0, 4)
    resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0)
    rosterResizeHandle.indicator = resizeIndicator

    -- Show indicator on hover (visual feedback only)
    rosterResizeHandle:SetScript("OnEnter", function(self)
        resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.6)
    end)
    rosterResizeHandle:SetScript("OnLeave", function(self)
        if not self.isResizing then
            resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0)
        end
    end)

    -- Resize logic
    rosterResizeHandle:RegisterForDrag("LeftButton")
    rosterResizeHandle.isResizing = false
    rosterResizeHandle.startX = nil
    rosterResizeHandle.startWidth = nil

    rosterResizeHandle:SetScript("OnDragStart", function(self)
        self.isResizing = true
        self.startX = GetCursorPosition() / UIParent:GetEffectiveScale()
        self.startWidth = rosterPanel:GetWidth()
        resizeIndicator:SetColorTexture(COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3], 0.8)
    end)

    rosterResizeHandle:SetScript("OnDragStop", function(self)
        self.isResizing = false
        self.startX = nil
        self.startWidth = nil
        resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0)

        -- Save the new width
        GB.rosterWidth = rosterPanel:GetWidth()
        ROSTER_WIDTH = GB.rosterWidth
        GB:SaveWindowPosition()
    end)

    -- Update size while dragging
    rosterResizeHandle:SetScript("OnUpdate", function(self)
        if not self.isResizing then return end
        -- Guard against nil values (shouldn't happen, but prevents jumps)
        if not self.startX or not self.startWidth then return end

        local currentX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local deltaX = self.startX - currentX  -- Dragging left increases width

        -- Only apply if there's meaningful movement (prevents jumps from tiny movements)
        if math.abs(deltaX) < 1 then return end

        local newWidth = math.max(MIN_ROSTER_WIDTH, math.min(MAX_ROSTER_WIDTH, self.startWidth + deltaX))

        -- Update roster panel width
        rosterPanel:SetWidth(newWidth)

        -- Update scroll frame right anchor to account for scrollbar
        rosterScrollFrame:SetPoint("BOTTOMRIGHT", -14, 4)

        -- Update content width
        rosterContent:SetWidth(newWidth - 18)

        -- Update chat scroll frame position
        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(newWidth + 24), 40)
        end

        -- Update chat scrollbar track position
        if scrollBarTrack then
            scrollBarTrack:SetPoint("TOPRIGHT", -(newWidth + 10), -100)
            scrollBarTrack:SetPoint("BOTTOMRIGHT", -(newWidth + 10), 40)
        end

        -- Update scrollbar
        updateRosterScrollBar()
    end)

    -- Function to update layout based on current roster width
    local function updateRosterLayout()
        local currentWidth = rosterPanel:GetWidth()

        -- Update chat scroll frame position
        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(currentWidth + 24), 40)
        end

        -- Update chat scrollbar track position
        if scrollBarTrack then
            scrollBarTrack:SetPoint("TOPRIGHT", -(currentWidth + 10), -100)
            scrollBarTrack:SetPoint("BOTTOMRIGHT", -(currentWidth + 10), 40)
        end

        -- Update roster content width
        rosterContent:SetWidth(currentWidth - 18)

        -- Update scrollbar
        updateRosterScrollBar()
    end
    self.updateRosterLayout = updateRosterLayout

    -- Apply initial layout with restored width
    updateRosterLayout()

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
