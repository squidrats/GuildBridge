local addonName, GB = ...

local MIN_WIDTH = 380
local MIN_HEIGHT = 280
local DEFAULT_WIDTH = 600
local DEFAULT_HEIGHT = 380
local DEFAULT_ROSTER_WIDTH = 140
local MIN_ROSTER_WIDTH = 80
local MAX_ROSTER_WIDTH = 250
local ROSTER_WIDTH = DEFAULT_ROSTER_WIDTH

local COLORS = {
    bgDark = { 0.05, 0.05, 0.06, 0.92 },
    bgMedium = { 0.08, 0.08, 0.09, 0.90 },
    bgLight = { 0.12, 0.12, 0.13, 0.85 },
    bgChat = { 0.03, 0.03, 0.04, 0.75 },

    border = { 0.20, 0.18, 0.16, 0.8 },
    borderLight = { 0.30, 0.28, 0.25, 0.6 },
    borderHighlight = { 0.45, 0.40, 0.35, 1 },

    guildGreen = { 0.25, 1.0, 0.25, 1 },
    guildGreenDark = { 0.15, 0.5, 0.15, 1 },
    guildGreenMuted = { 0.20, 0.45, 0.20, 1 },

    accentGold = { 1, 0.82, 0, 1 },
    accentGoldDim = { 0.8, 0.65, 0, 0.8 },

    textNormal = { 0.90, 0.88, 0.85, 1 },
    textMuted = { 0.55, 0.52, 0.48, 1 },
    textHighlight = { 1, 1, 1, 1 },
    textGuild = { 0.25, 1.0, 0.25, 1 },

    tabNormal = { 0.10, 0.10, 0.11, 0.85 },
    tabSelected = { 0.12, 0.14, 0.12, 0.95 },
    tabHover = { 0.15, 0.17, 0.15, 0.90 },

    statusGreen = { 0.2, 0.9, 0.2, 1 },
    statusRed = { 0.9, 0.25, 0.25, 1 },
    statusYellow = { 0.9, 0.8, 0.2, 1 },

    inputBg = { 0.06, 0.06, 0.07, 0.9 },
    inputBorder = { 0.25, 0.35, 0.25, 0.8 },
}

local updateTabHighlights
local updatePageTabSelection
local updatePageVisibility
local createTab
local createPageTab
local showContextMenu
local showRealmInputDialog

local contextMenu
local forgetButton
local setRealmButton
local realmInputDialog
local allTabContextMenu
local forgetAllButton
local copyTextDialog

updateTabHighlights = function()
    for _, tab in pairs(GB.tabButtons) do
        if tab.filterValue == GB.currentFilter then
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

function GB:UpdateConnectionIndicators()
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
            local isMyGuild = (tab.filterValue == myFilterKey)
            if isMyGuild then
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
            elseif self:HasConnectedUserInGuild(tab.filterValue) then
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
            else
                tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Red")
                tab.statusDot:SetVertexColor(unpack(COLORS.statusRed))
            end
        end
    end

    self:ScheduleRefreshRoster()
end

local function hexToRGB(hex)
    if not hex or #hex ~= 6 then return 1, 1, 1 end
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

function GB:ScheduleRefreshRoster()
    if self.refreshRosterPending then
        return
    end
    self.refreshRosterPending = true
    C_Timer.After(self.REFRESH_ROSTER_DEBOUNCE, function()
        GB.refreshRosterPending = false
        GB:RefreshRoster()
    end)
end

function GB:RefreshRoster()
    if not self.rosterContent or not self.rosterPanel then return end

    if self.currentPage ~= "chat" then
        self.rosterPanel:Hide()
        return
    end
    self.rosterPanel:Show()

    for _, entry in ipairs(self.rosterEntries) do
        entry:Hide()
    end

    local members = {}
    local seenMembers = {}
    local now = GetTime()

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

    local function addMember(member)
        local key = (member.name or "?") .. "-" .. (member.realm or "")
        if not seenMembers[key] then
            seenMembers[key] = true
            table.insert(members, member)
        end
    end

    for filterKey, roster in pairs(self.guildRosters or {}) do
        if roster.members then
            local guildInfo = self.knownGuilds[filterKey]
            local guildName = guildInfo and guildInfo.guildName or "Unknown"
            local guildHomeRealm = guildInfo and guildInfo.guildHomeRealm or nil

            for memberKey, info in pairs(roster.members) do
                local displayRealm = info.realm or guildHomeRealm

                addMember({
                    name = info.name or memberKey,
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

    if myGuildName and myGuildClubId and self:IsAllowedGuildId(myGuildClubId) then
        local playerName = UnitName("player")
        local playerRealm = GetRealmName()
        local _, _, _, _, _, _, _, _, _, _, playerClass = GetPlayerInfoByGUID(UnitGUID("player"))

        local key = playerName .. "-" .. (playerRealm or "")
        if seenMembers[key] then
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

    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if now - info.lastSeen < 300 then
            local name = info.characterName
            local realm = info.characterRealm or info.realmName
            if name then
                local key = name .. "-" .. (realm or "")
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

    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 90 then
            local name, realm = strsplit("-", altName)
            if name then
                for _, m in ipairs(members) do
                    if m.name == name and (m.realm == realm or (not m.realm and not realm)) then
                        m.isWhisper = true
                        break
                    end
                end
            end
        end
    end

    local filteredMembers = {}
    for _, member in ipairs(members) do
        if self.currentFilter == nil then
            table.insert(filteredMembers, member)
        elseif member.filterKey == self.currentFilter then
            table.insert(filteredMembers, member)
        end
    end

    table.sort(filteredMembers, function(a, b)
        if a.isMe then return true end
        if b.isMe then return false end
        return (a.name or "") < (b.name or "")
    end)

    local headerText = "Online (" .. #filteredMembers .. ")"
    self.rosterHeader:SetText(headerText)

    local yOffset = 0
    local entryHeight = 16
    local partyIconSize = 12
    for i, member in ipairs(filteredMembers) do
        local entry = self.rosterEntries[i]
        if not entry then
            entry = CreateFrame("Frame", nil, self.rosterContent)
            entry:SetSize(ROSTER_WIDTH - 30, entryHeight)

            entry.partyIcon = entry:CreateTexture(nil, "OVERLAY")
            entry.partyIcon:SetSize(partyIconSize, partyIconSize)
            entry.partyIcon:SetPoint("LEFT", 1, 0)
            entry.partyIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            entry.partyIcon:SetVertexColor(0.4, 0.8, 1.0, 1)
            entry.partyIcon:Hide()

            entry.nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
            entry.nameText:SetPoint("LEFT", 2, 0)
            entry.nameText:SetJustifyH("LEFT")
            entry.nameText:SetWidth(ROSTER_WIDTH - 34)
            entry.nameText:SetWordWrap(false)

            entry.highlight = entry:CreateTexture(nil, "BACKGROUND")
            entry.highlight:SetAllPoints()
            entry.highlight:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.3)
            entry.highlight:Hide()

            entry:EnableMouse(true)
            entry:SetScript("OnEnter", function(self)
                self.highlight:Show()
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
                if not self.memberData.isMe then
                    GameTooltip:AddLine("Ctrl+Click to invite", 0.5, 0.5, 0.5)
                end
                GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            entry:SetScript("OnLeave", function(self)
                self.highlight:Hide()
                GameTooltip:Hide()
            end)

            entry:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    GB:ShowRosterContextMenu(self.memberData)
                elseif button == "LeftButton" and IsControlKeyDown() then
                    local memberName = self.memberData.name
                    local memberRealm = self.memberData.realm
                    if memberName then
                        local fullName = memberName
                        if memberRealm and memberRealm ~= "" then
                            fullName = memberName .. "-" .. memberRealm
                        end
                        if not self.memberData.isMe then
                            C_PartyInfo.InviteUnit(fullName)
                            print("|cff00ff00MNet:|r Invited " .. fullName .. " to party")
                        end
                    end
                end
            end)

            self.rosterEntries[i] = entry
        end

        entry.memberData = member
        entry:SetPoint("TOPLEFT", 0, -yOffset)

        local inParty = self:IsInMyParty(member.name, member.realm) or self:IsInAnyParty(member.name, member.realm)
        member.inParty = inParty

        if inParty then
            entry.partyIcon:Show()
            entry.nameText:SetPoint("LEFT", partyIconSize + 2, 0)
            entry.nameText:SetWidth(ROSTER_WIDTH - 34 - partyIconSize)
        else
            entry.partyIcon:Hide()
            entry.nameText:SetPoint("LEFT", 2, 0)
            entry.nameText:SetWidth(ROSTER_WIDTH - 34)
        end

        local displayName = member.name or "Unknown"
        if member.realm and member.realm ~= "" then
            displayName = displayName .. "-" .. member.realm
        end
        if member.isMe then
            displayName = displayName .. " *"
        end

        local r, g, b = 1, 1, 1
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

    self.rosterContent:SetHeight(math.max(1, yOffset))

    if self.updateRosterScrollBar then
        self.updateRosterScrollBar()
    end
end

function GB:ShowRosterContextMenu(memberData)
    if not memberData or memberData.isMe then return end

    local fullName = memberData.name
    if memberData.realm and memberData.realm ~= "" then
        fullName = memberData.name .. "-" .. memberData.realm
    end

    if Menu and Menu.GetManager then
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
        SetItemRef("player:" .. fullName, "|Hplayer:" .. fullName .. "|h[" .. fullName .. "]|h", "RightButton")
    end
end

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

local function setGuildRealm(filterKey, newRealm)
    if filterKey and GB.knownGuilds[filterKey] then
        GB.knownGuilds[filterKey].realmName = newRealm
        GB.knownGuilds[filterKey].manualRealm = true
        MNetDB.knownGuilds = GB.knownGuilds
        GB:RebuildTabs()
    end
end

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

    for filterKey, _ in pairs(GB.knownGuilds) do
        if filterKey ~= myFilterKey then
            GB.knownGuilds[filterKey] = nil
        end
    end
    MNetDB.knownGuilds = GB.knownGuilds

    GB.currentFilter = nil
    GB:RebuildTabs()
    GB:RefreshMessages()
end

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

local function showAllTabContextMenu()
    ensureAllTabContextMenu()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    allTabContextMenu:ClearAllPoints()
    allTabContextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    allTabContextMenu:Show()
end

local function stripColorCodes(text)
    if not text then return "" end
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("||", "|")
    return text
end

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

    local cleanText = stripColorCodes(text)
    copyTextDialog.editBox:SetText(cleanText)
    copyTextDialog:Show()
    copyTextDialog.editBox:HighlightText()
    copyTextDialog.editBox:SetFocus()
end

GB.ShowCopyTextDialog = showCopyTextDialog

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

function GB:ShowCopyChatMenu()
    ensureCopyChatMenu()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    copyChatMenu:ClearAllPoints()
    copyChatMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    copyChatMenu:Show()
end

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

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(unpack(COLORS.tabNormal))
    tab.bg = bg

    local borderTop = tab:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", 0, 0)
    borderTop:SetHeight(2)
    borderTop:SetColorTexture(0, 0, 0, 0)
    tab.borderTop = borderTop

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

    local borderBottom = tab:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(unpack(COLORS.borderLight))
    tab.borderBottom = borderBottom

    if guildName then
        tab.statusDot = tab:CreateTexture(nil, "OVERLAY")
        tab.statusDot:SetSize(14, 14)
        tab.statusDot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -3, -3)
        tab.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
        tab.statusDot:SetVertexColor(unpack(COLORS.statusGreen))
    end

    tab.guildText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if realmLabel and realmLabel ~= "" then
        tab.guildText:SetPoint("TOP", tab, "TOP", 0, -7)
    else
        tab.guildText:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
    tab.guildText:SetText(guildLabel)
    tab.guildText:SetTextColor(unpack(COLORS.textNormal))

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
            GB:ScheduleRefreshRoster()
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

updatePageTabSelection = function()
    for i, tab in ipairs(GB.pageTabs) do
        if tab.pageName == GB.currentPage then
            tab.bg:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.9)
            tab.text:SetTextColor(1, 1, 1, 1)
        else
            tab.bg:SetColorTexture(0, 0, 0, 0.3)
            tab.text:SetTextColor(unpack(COLORS.textMuted))
        end
    end
end

createPageTab = function(parent, label, tabIndex, pageName, isFirst, isLast)
    local tab = CreateFrame("Button", "MNetPageTab" .. tabIndex, parent)
    tab:SetSize(55, 22)
    tab:SetID(tabIndex)
    tab.pageName = pageName

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0, 0, 0, 0.3)

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

local function createPageTabs()
    if not GB.mainFrame then return end

    for _, tab in pairs(GB.pageTabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    GB.pageTabs = {}

    if not GB.pageTabContainer then
        GB.pageTabContainer = CreateFrame("Frame", nil, GB.mainFrame, "BackdropTemplate")
    end
    local container = GB.pageTabContainer
    container:SetSize(168, 24)
    container:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 8, -28)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
    container:SetBackdropBorderColor(COLORS.guildGreenDark[1], COLORS.guildGreenDark[2], COLORS.guildGreenDark[3], 0.8)
    container:Show()

    GB.pageTabs[1] = createPageTab(container, "Chat", 1, "chat", true, false)
    GB.pageTabs[1]:SetPoint("LEFT", container, "LEFT", 1, 0)

    GB.pageTabs[2] = createPageTab(container, "Status", 2, "status", false, false)
    GB.pageTabs[2]:SetPoint("LEFT", GB.pageTabs[1], "RIGHT", 0, 0)

    GB.pageTabs[3] = createPageTab(container, "Debug", 3, "debug", false, true)
    GB.pageTabs[3]:SetPoint("LEFT", GB.pageTabs[2], "RIGHT", 0, 0)

    if not GB.tabSeparator then
        GB.tabSeparator = GB.mainFrame:CreateTexture(nil, "ARTWORK")
    end
    GB.tabSeparator:SetPoint("TOPLEFT", GB.mainFrame, "TOPLEFT", 8, -56)
    GB.tabSeparator:SetPoint("TOPRIGHT", GB.mainFrame, "TOPRIGHT", -8, -56)
    GB.tabSeparator:SetHeight(1)
    GB.tabSeparator:SetColorTexture(COLORS.borderLight[1], COLORS.borderLight[2], COLORS.borderLight[3], 0.5)

    updatePageTabSelection()
end

updatePageVisibility = function()
    if not GB.mainFrame then return end

    for key, tab in pairs(GB.tabButtons) do
        if key:match("^guild") or key == "all" then
            if GB.currentPage == "chat" then
                tab:Show()
            else
                tab:Hide()
            end
        end
    end

    if GB.tabSeparator then
        if GB.currentPage == "chat" then
            GB.tabSeparator:Show()
        else
            GB.tabSeparator:Hide()
        end
    end

    updatePageTabSelection()

    if GB.scrollFrame then
        local titleBarHeight = 26
        local pageTabHeight = 32
        local separatorHeight = 4
        local scrollTopOffset
        if GB.currentPage == "chat" then
            local tabWidth = 80
            local tabSpacing = 3
            local rowHeight = 38
            local maxWidth = GB.mainFrame:GetWidth() - 16
            local guildCount = 1
            for _ in pairs(GB.knownGuilds) do
                guildCount = guildCount + 1
            end
            local tabsPerRow = math.max(1, math.floor(maxWidth / (tabWidth + tabSpacing)))
            local numRows = math.ceil(guildCount / tabsPerRow)
            if numRows < 1 then numRows = 1 end
            scrollTopOffset = titleBarHeight + pageTabHeight + separatorHeight + (numRows * rowHeight) + 4
        else
            scrollTopOffset = titleBarHeight + pageTabHeight + 8
        end
        GB.scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        if GB.scrollBarTrack then
            GB.scrollBarTrack:SetPoint("TOPRIGHT", -(ROSTER_WIDTH + 10), -scrollTopOffset)
        end
        if GB.rosterPanel then
            GB.rosterPanel:SetPoint("TOPRIGHT", -8, -scrollTopOffset)
        end
    end

    if GB.currentPage == "debug" then
        if GB.debugDisplay then
            GB.debugDisplay:Show()
        end
        if GB.scrollFrame then
            GB.scrollFrame:Hide()
        end
        if GB.rosterPanel then
            GB.rosterPanel:Hide()
        end
        if GB.scrollBarTrack then
            GB.scrollBarTrack:Hide()
        end
    else
        if GB.debugDisplay then
            GB.debugDisplay:Hide()
        end
        if GB.scrollFrame then
            GB.scrollFrame:Show()
        end
        if GB.rosterPanel then
            GB.rosterPanel:Show()
        end
        if GB.scrollBarTrack then
            GB.scrollBarTrack:Show()
        end
    end

    if GB.currentPage == "chat" or GB.currentPage == "status" then
        GB:RefreshMessages()
    end
    GB:ScheduleRefreshRoster()
end

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
    local pageTabHeight = 32
    local separatorHeight = 4
    local topRowY = -(titleBarHeight + pageTabHeight + separatorHeight)

    local myGuildName = GetGuildInfo("player")
    local xOffset = 8
    local yOffset = topRowY
    local maxWidth = self.mainFrame:GetWidth() - 16
    local tabIndex = 1

    self.tabButtons.all = createTab(self.mainFrame, "All", nil, nil, xOffset, yOffset, nil, tabWidth)
    xOffset = xOffset + tabWidth + tabSpacing

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

    if myFilterKey and self.knownGuilds[myFilterKey] then
        local info = self.knownGuilds[myFilterKey]
        local short = self.guildShortNames[info.guildName] or info.guildName or "?"
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

    for filterKey, info in pairs(self.knownGuilds) do
        if filterKey ~= myFilterKey then
            if xOffset + tabWidth > maxWidth then
                xOffset = 8
                yOffset = yOffset - rowHeight
            end

            local short = self.guildShortNames[info.guildName] or info.guildName or "?"
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
            self.tabButtons["guild" .. tabIndex] = createTab(self.mainFrame, short, realmLabel, filterKey, xOffset, yOffset, info.guildName, tabWidth)
            xOffset = xOffset + tabWidth + tabSpacing
            tabIndex = tabIndex + 1
        end
    end

    updatePageVisibility()
    updateTabHighlights()
    self:UpdateConnectionIndicators()
end

function GB:CreateBridgeUI()
    if self.mainFrame then
        return
    end

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

    self.mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    self.mainFrame:SetBackdropColor(unpack(COLORS.bgDark))
    self.mainFrame:SetBackdropBorderColor(unpack(COLORS.border))

    local titleBar = self.mainFrame:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:SetColorTexture(unpack(COLORS.bgMedium))
    self.mainFrame.titleBar = titleBar

    local titleBorder = self.mainFrame:CreateTexture(nil, "ARTWORK")
    titleBorder:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleBorder:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleBorder:SetHeight(1)
    titleBorder:SetColorTexture(COLORS.guildGreenDark[1], COLORS.guildGreenDark[2], COLORS.guildGreenDark[3], 0.5)

    self.mainFrame:RegisterForDrag("LeftButton")
    self.mainFrame:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    self.mainFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        GB:SaveWindowPosition()
    end)

    local hordeIcon = self.mainFrame:CreateTexture(nil, "OVERLAY")
    hordeIcon:SetSize(18, 18)
    hordeIcon:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    hordeIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Horde")
    hordeIcon:SetTexCoord(0, 1, 0, 1)

    self.mainFrame.title = self.mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.mainFrame.title:SetPoint("LEFT", hordeIcon, "RIGHT", 6, 0)
    self.mainFrame.title:SetText("MNet")
    self.mainFrame.title:SetTextColor(unpack(COLORS.guildGreen))

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

    local resizeGrip = CreateFrame("Frame", nil, self.mainFrame)
    resizeGrip:SetSize(24, 24)
    resizeGrip:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeGrip:EnableMouse(true)

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

    self.mainFrame:SetScript("OnSizeChanged", function(frame, width, height)
        local currentRosterWidth = GB.rosterWidth or ROSTER_WIDTH
        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(currentRosterWidth + 24), 40)
        end
    end)

    createPageTabs()

    self:RebuildTabs()

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

    self.debugDisplay = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    self.debugDisplay:SetPoint("TOPLEFT", 10, -68)
    self.debugDisplay:SetPoint("BOTTOMRIGHT", -(ROSTER_WIDTH + 10), 40)
    self.debugDisplay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    self.debugDisplay:SetBackdropColor(unpack(COLORS.bgChat))
    self.debugDisplay:SetBackdropBorderColor(unpack(COLORS.border))
    self.debugDisplay:Hide()

    local debugScrollFrame = CreateFrame("ScrollFrame", nil, self.debugDisplay)
    debugScrollFrame:SetPoint("TOPLEFT", 8, -8)
    debugScrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)

    local debugEditBox = CreateFrame("EditBox", nil, debugScrollFrame)
    debugEditBox:SetMultiLine(true)
    debugEditBox:SetAutoFocus(false)
    debugEditBox:SetFontObject(GameFontHighlightSmall)
    debugEditBox:SetTextColor(unpack(COLORS.textNormal))
    debugEditBox:SetWidth(debugScrollFrame:GetWidth() - 16)
    debugEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    debugEditBox:EnableMouse(true)
    debugEditBox:SetScript("OnChar", function(self) end)
    debugEditBox:SetScript("OnKeyDown", function(self, key)
        if key ~= "C" and not IsControlKeyDown() and key ~= "A" then
            if key ~= "UP" and key ~= "DOWN" and key ~= "LEFT" and key ~= "RIGHT"
               and key ~= "HOME" and key ~= "END" and key ~= "PAGEUP" and key ~= "PAGEDOWN" then
                return
            end
        end
    end)
    debugEditBox:SetScript("OnTextChanged", function(self)
        if self._settingText then return end
        self._settingText = true
        self:SetText(self._lastText or "")
        self._settingText = false
    end)

    debugScrollFrame:SetScrollChild(debugEditBox)

    local debugScrollBar = CreateFrame("Slider", nil, debugScrollFrame, "UIPanelScrollBarTemplate")
    debugScrollBar:SetPoint("TOPLEFT", debugScrollFrame, "TOPRIGHT", 4, -16)
    debugScrollBar:SetPoint("BOTTOMLEFT", debugScrollFrame, "BOTTOMRIGHT", 4, 16)
    debugScrollBar:SetMinMaxValues(0, 100)
    debugScrollBar:SetValueStep(20)
    debugScrollBar:SetWidth(16)
    debugScrollBar:SetScript("OnValueChanged", function(self, value)
        debugScrollFrame:SetVerticalScroll(value)
    end)

    debugScrollFrame:EnableMouseWheel(true)
    debugScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = debugScrollBar:GetValue()
        local minVal, maxVal = debugScrollBar:GetMinMaxValues()
        if delta > 0 then
            debugScrollBar:SetValue(math.max(minVal, current - 40))
        else
            debugScrollBar:SetValue(math.min(maxVal, current + 40))
        end
    end)

    self.debugEditBox = debugEditBox
    self.debugScrollFrame = debugScrollFrame
    self.debugScrollBar = debugScrollBar

    C_Timer.NewTicker(1, function()
        if GB.currentPage == "debug" and GB.debugDisplay:IsShown() then
            GB:UpdateDebugDisplay()
        end
    end)

    local chatScrollFrame = CreateFrame("ScrollFrame", nil, self.mainFrame)
    chatScrollFrame:SetPoint("TOPLEFT", 10, -100)
    chatScrollFrame:SetPoint("BOTTOMRIGHT", -(ROSTER_WIDTH + 24), 40)

    local scrollBg = chatScrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(unpack(COLORS.bgChat))

    local chatEditBox = CreateFrame("EditBox", nil, chatScrollFrame)
    chatEditBox:SetMultiLine(true)
    chatEditBox:SetAutoFocus(false)
    chatEditBox:SetFontObject(ChatFontNormal)
    chatEditBox:SetTextColor(unpack(COLORS.textNormal))
    chatEditBox:SetWidth(chatScrollFrame:GetWidth() or 300)
    chatEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    chatEditBox:EnableMouse(true)
    chatEditBox:SetHyperlinksEnabled(true)

    chatEditBox:SetScript("OnChar", function(self) end)
    chatEditBox:SetScript("OnKeyDown", function(self, key)
        if IsControlKeyDown() and (key == "C" or key == "A") then
            return
        end
        if key == "BACKSPACE" or key == "DELETE" or key == "ENTER" then
            return
        end
    end)

    chatEditBox:SetScript("OnTextChanged", function(self)
        if self.expectedText and self:GetText() ~= self.expectedText then
            self:SetText(self.expectedText)
        end
    end)

    chatScrollFrame:SetScrollChild(chatEditBox)
    self.chatScrollFrame = chatScrollFrame
    self.chatEditBox = chatEditBox

    local clickCatcher = CreateFrame("Frame", nil, UIParent)
    clickCatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
    clickCatcher:SetScript("OnEvent", function(frame, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if chatEditBox:HasFocus() and not MouseIsOver(chatEditBox) and not MouseIsOver(chatScrollFrame) then
                chatEditBox:ClearFocus()
                chatEditBox:HighlightText(0, 0)
            end
        end
    end)

    self.scrollFrame = {
        _editBox = chatEditBox,
        _scrollFrame = chatScrollFrame,
        _messages = {},
        _maxLines = 500,
        _isRefreshing = false,

        AddMessage = function(self, msg)
            table.insert(self._messages, msg)
            while #self._messages > self._maxLines do
                table.remove(self._messages, 1)
            end
            local fullText = table.concat(self._messages, "\n")
            self._editBox.expectedText = fullText
            self._editBox:SetText(fullText)
            -- Only auto-scroll to bottom for new incoming messages, not during refresh
            if not self._isRefreshing then
                C_Timer.After(0.01, function()
                    local scrollMax = self._scrollFrame:GetVerticalScrollRange()
                    self._scrollFrame:SetVerticalScroll(scrollMax)
                    if GB.updateScrollBar then
                        GB.updateScrollBar()
                    end
                end)
            end
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
            return 0
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

    local scrollBarTrack = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    scrollBarTrack:SetPoint("TOPRIGHT", -(ROSTER_WIDTH + 10), -100)
    scrollBarTrack:SetPoint("BOTTOMRIGHT", -(ROSTER_WIDTH + 10), 40)
    scrollBarTrack:SetWidth(12)
    scrollBarTrack:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollBarTrack:SetBackdropColor(0.05, 0.05, 0.06, 0.8)
    scrollBarTrack:SetBackdropBorderColor(unpack(COLORS.borderLight))

    local scrollBar = CreateFrame("Slider", nil, scrollBarTrack)
    scrollBar:SetPoint("TOPLEFT", 1, -1)
    scrollBar:SetPoint("BOTTOMRIGHT", -1, 1)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(1)
    scrollBar:SetValueStep(1)
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetObeyStepOnDrag(true)
    self.scrollBar = scrollBar
    self.scrollBarTrack = scrollBarTrack

    local thumbTexture = scrollBar:CreateTexture(nil, "OVERLAY")
    thumbTexture:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.7)
    thumbTexture:SetSize(10, 30)
    scrollBar:SetThumbTexture(thumbTexture)

    local updatingScrollBar = false

    local function updateScrollBar()
        local scrollMax = chatScrollFrame:GetVerticalScrollRange()

        if scrollMax <= 0 then
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

    scrollBar:SetScript("OnValueChanged", function(bar, value)
        if updatingScrollBar then return end
        chatScrollFrame:SetVerticalScroll(value)
    end)

    scrollBar:SetScript("OnMouseWheel", function(bar, delta)
        local current = chatScrollFrame:GetVerticalScroll()
        local scrollMax = chatScrollFrame:GetVerticalScrollRange()
        local step = 42
        if delta > 0 then
            chatScrollFrame:SetVerticalScroll(math.max(0, current - step))
        else
            chatScrollFrame:SetVerticalScroll(math.min(scrollMax, current + step))
        end
        updateScrollBar()
    end)

    chatScrollFrame:EnableMouseWheel(true)
    chatScrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        local current = frame:GetVerticalScroll()
        local scrollMax = frame:GetVerticalScrollRange()
        local step = 42
        if delta > 0 then
            frame:SetVerticalScroll(math.max(0, current - step))
        else
            frame:SetVerticalScroll(math.min(scrollMax, current + step))
        end
        updateScrollBar()
    end)

    chatEditBox:SetScript("OnHyperlinkClick", function(frame, link, text, button)
        SetItemRef(link, text, button)
    end)

    chatScrollFrame:HookScript("OnShow", updateScrollBar)

    chatScrollFrame:SetScript("OnSizeChanged", function(frame, width, height)
        chatEditBox:SetWidth(width)
        updateScrollBar()
    end)

    if self.rosterWidth then
        ROSTER_WIDTH = math.max(MIN_ROSTER_WIDTH, math.min(MAX_ROSTER_WIDTH, self.rosterWidth))
    else
        ROSTER_WIDTH = DEFAULT_ROSTER_WIDTH
        self.rosterWidth = ROSTER_WIDTH
    end

    local rosterPanel = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    rosterPanel:SetPoint("TOPRIGHT", -8, -100)
    rosterPanel:SetPoint("BOTTOMRIGHT", -8, 40)
    rosterPanel:SetWidth(ROSTER_WIDTH)
    rosterPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    rosterPanel:SetBackdropColor(0.04, 0.04, 0.05, 0.85)
    rosterPanel:SetBackdropBorderColor(unpack(COLORS.borderLight))
    self.rosterPanel = rosterPanel

    local rosterHeader = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rosterHeader:SetPoint("TOP", rosterPanel, "TOP", 0, -6)
    rosterHeader:SetText("Online")
    rosterHeader:SetTextColor(unpack(COLORS.guildGreen))
    self.rosterHeader = rosterHeader

    local rosterScrollFrame = CreateFrame("ScrollFrame", nil, rosterPanel)
    rosterScrollFrame:SetPoint("TOPLEFT", 4, -22)
    rosterScrollFrame:SetPoint("BOTTOMRIGHT", -14, 4)

    local rosterContent = CreateFrame("Frame", nil, rosterScrollFrame)
    rosterContent:SetSize(ROSTER_WIDTH - 18, 1)
    rosterScrollFrame:SetScrollChild(rosterContent)
    self.rosterContent = rosterContent
    self.rosterScrollFrame = rosterScrollFrame

    local rosterScrollTrack = CreateFrame("Frame", nil, rosterPanel, "BackdropTemplate")
    rosterScrollTrack:SetPoint("TOPRIGHT", -4, -22)
    rosterScrollTrack:SetPoint("BOTTOMRIGHT", -4, 4)
    rosterScrollTrack:SetWidth(8)
    rosterScrollTrack:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    rosterScrollTrack:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

    local rosterScrollBar = CreateFrame("Slider", nil, rosterScrollTrack)
    rosterScrollBar:SetPoint("TOPLEFT", 0, 0)
    rosterScrollBar:SetPoint("BOTTOMRIGHT", 0, 0)
    rosterScrollBar:SetOrientation("VERTICAL")
    rosterScrollBar:SetMinMaxValues(0, 1)
    rosterScrollBar:SetValue(0)
    rosterScrollBar:SetObeyStepOnDrag(true)
    rosterScrollBar:SetValueStep(1)

    local rosterThumbTexture = rosterScrollBar:CreateTexture(nil, "OVERLAY")
    rosterThumbTexture:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.7)
    rosterThumbTexture:SetSize(8, 30)
    rosterScrollBar:SetThumbTexture(rosterThumbTexture)

    local updatingRosterScrollBar = false

    local function updateRosterScrollBar()
        local contentHeight = rosterContent:GetHeight()
        local viewportHeight = rosterScrollFrame:GetHeight()

        if contentHeight <= viewportHeight or contentHeight <= 0 then
            rosterScrollTrack:Hide()
            rosterScrollFrame:SetVerticalScroll(0)
            return
        end

        rosterScrollTrack:Show()

        local trackHeight = rosterScrollTrack:GetHeight()
        local thumbRatio = viewportHeight / contentHeight
        local thumbHeight = math.max(20, math.min(trackHeight, trackHeight * thumbRatio))
        rosterThumbTexture:SetHeight(thumbHeight)

        local maxScroll = contentHeight - viewportHeight

        updatingRosterScrollBar = true
        rosterScrollBar:SetMinMaxValues(0, maxScroll)
        rosterScrollBar:SetValue(rosterScrollFrame:GetVerticalScroll())
        updatingRosterScrollBar = false
    end
    self.updateRosterScrollBar = updateRosterScrollBar

    rosterScrollBar:SetScript("OnValueChanged", function(bar, value)
        if updatingRosterScrollBar then return end
        rosterScrollFrame:SetVerticalScroll(value)
    end)

    rosterPanel:EnableMouseWheel(true)
    rosterPanel:SetScript("OnMouseWheel", function(frame, delta)
        local contentHeight = rosterContent:GetHeight()
        local viewportHeight = rosterScrollFrame:GetHeight()
        if contentHeight <= viewportHeight then return end

        local maxScroll = contentHeight - viewportHeight
        local scrollStep = 16 * 2
        local currentScroll = rosterScrollFrame:GetVerticalScroll()
        local newScroll = currentScroll - (delta * scrollStep)

        newScroll = math.max(0, math.min(maxScroll, newScroll))
        rosterScrollFrame:SetVerticalScroll(newScroll)
        updateRosterScrollBar()
    end)

    rosterScrollFrame:EnableMouseWheel(true)
    rosterScrollFrame:SetScript("OnMouseWheel", function(frame, delta)
        rosterPanel:GetScript("OnMouseWheel")(rosterPanel, delta)
    end)

    self.rosterEntries = {}

    local rosterResizeHandle = CreateFrame("Frame", nil, rosterPanel)
    rosterResizeHandle:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 0, 0)
    rosterResizeHandle:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 0, 0)
    rosterResizeHandle:SetWidth(6)
    rosterResizeHandle:EnableMouse(true)

    local resizeIndicator = rosterResizeHandle:CreateTexture(nil, "OVERLAY")
    resizeIndicator:SetPoint("LEFT", 1, 0)
    resizeIndicator:SetSize(2, 0)
    resizeIndicator:SetPoint("TOP", 0, -4)
    resizeIndicator:SetPoint("BOTTOM", 0, 4)
    resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0)
    rosterResizeHandle.indicator = resizeIndicator

    rosterResizeHandle:SetScript("OnEnter", function(self)
        resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0.6)
    end)
    rosterResizeHandle:SetScript("OnLeave", function(self)
        if not self.isResizing then
            resizeIndicator:SetColorTexture(COLORS.guildGreenMuted[1], COLORS.guildGreenMuted[2], COLORS.guildGreenMuted[3], 0)
        end
    end)

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

        GB.rosterWidth = rosterPanel:GetWidth()
        ROSTER_WIDTH = GB.rosterWidth
        GB:SaveWindowPosition()
    end)

    rosterResizeHandle:SetScript("OnUpdate", function(self)
        if not self.isResizing then return end
        if not self.startX or not self.startWidth then return end

        local currentX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local deltaX = self.startX - currentX

        if math.abs(deltaX) < 1 then return end

        local newWidth = math.max(MIN_ROSTER_WIDTH, math.min(MAX_ROSTER_WIDTH, self.startWidth + deltaX))

        rosterPanel:SetWidth(newWidth)

        rosterScrollFrame:SetPoint("BOTTOMRIGHT", -14, 4)

        rosterContent:SetWidth(newWidth - 18)

        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(newWidth + 24), 40)
        end

        if scrollBarTrack then
            scrollBarTrack:SetPoint("TOPRIGHT", -(newWidth + 10), -100)
            scrollBarTrack:SetPoint("BOTTOMRIGHT", -(newWidth + 10), 40)
        end

        updateRosterScrollBar()
    end)

    local function updateRosterLayout()
        local currentWidth = rosterPanel:GetWidth()

        if GB.scrollFrame then
            GB.scrollFrame:SetPoint("BOTTOMRIGHT", -(currentWidth + 24), 40)
        end

        if scrollBarTrack then
            scrollBarTrack:SetPoint("TOPRIGHT", -(currentWidth + 10), -100)
            scrollBarTrack:SetPoint("BOTTOMRIGHT", -(currentWidth + 10), 40)
        end

        rosterContent:SetWidth(currentWidth - 18)

        updateRosterScrollBar()
    end
    self.updateRosterLayout = updateRosterLayout

    updateRosterLayout()

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

    self.inputBox:SetScript("OnEditFocusGained", function()
        inputBg:SetBackdropBorderColor(COLORS.guildGreen[1], COLORS.guildGreen[2], COLORS.guildGreen[3], 0.7)
    end)
    self.inputBox:SetScript("OnEditFocusLost", function()
        inputBg:SetBackdropBorderColor(unpack(COLORS.inputBorder))
    end)

    self:RestoreWindowPosition()

    self.mainFrame:Hide()

    self.mainFrame:SetScript("OnHide", function()
        GB:SaveWindowPosition()
    end)
end

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

function GB:UpdateDebugDisplay()
    if not self.debugEditBox then return end

    local now = GetTime()
    local elapsed = now - self.trafficStats.lastReset
    if elapsed == 0 then elapsed = 1 end

    local total = self.trafficStats.bnet + self.trafficStats.whisper + self.trafficStats.guild

    local bnetCount = 0
    for _ in pairs(self.connectedBridgeUsers) do
        bnetCount = bnetCount + 1
    end
    local altCount = 0
    for _ in pairs(self.connectedWhisperAlts) do
        altCount = altCount + 1
    end

    local lines = {}
    table.insert(lines, "|cff00ff00=== MNET TRAFFIC DEBUG ===|r")
    table.insert(lines, string.format("Uptime: %ds | Total: %d msgs (%.1f/sec)", math.floor(elapsed), total, total/elapsed))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700MESSAGE COUNTS (BY CHANNEL)|r")
    table.insert(lines, string.format("  BNet:        %6d msgs  (%.2f/sec)", self.trafficStats.bnet, self.trafficStats.bnet / elapsed))
    table.insert(lines, string.format("  Whisper:     %6d msgs  (%.2f/sec)", self.trafficStats.whisper, self.trafficStats.whisper / elapsed))
    table.insert(lines, string.format("  Guild Relay: %6d msgs  (%.2f/sec)", self.trafficStats.guild, self.trafficStats.guild / elapsed))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700MESSAGE BREAKDOWN (BY TYPE)|r")
    table.insert(lines, string.format("  Handshakes:   %6d msgs  (%.2f/sec)", self.trafficStats.handshakes or 0, (self.trafficStats.handshakes or 0) / elapsed))
    table.insert(lines, string.format("  Roster Full:  %6d msgs  (%.2f/sec)", self.trafficStats.rosterFull or 0, (self.trafficStats.rosterFull or 0) / elapsed))
    table.insert(lines, string.format("  Roster Delta: %6d msgs  (%.2f/sec)", self.trafficStats.rosterDelta or 0, (self.trafficStats.rosterDelta or 0) / elapsed))
    table.insert(lines, string.format("  Roster Req:   %6d msgs  (%.2f/sec)", self.trafficStats.rosterRequest or 0, (self.trafficStats.rosterRequest or 0) / elapsed))
    table.insert(lines, string.format("  Party:        %6d msgs  (%.2f/sec)", self.trafficStats.party or 0, (self.trafficStats.party or 0) / elapsed))
    table.insert(lines, string.format("  Chat:         %6d msgs  (%.2f/sec)", self.trafficStats.chat or 0, (self.trafficStats.chat or 0) / elapsed))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700QUEUE STATUS|r")
    local queueColor1 = #self.outgoingQueue > 20 and "|cffff0000" or "|cffffffff"
    local queueColor2 = #self.guildRelayQueue > 10 and "|cffff0000" or "|cffffffff"
    table.insert(lines, string.format("  BNet/Whisper: %s%3d msgs|r %s", queueColor1, #self.outgoingQueue, #self.outgoingQueue > 20 and "|cffff0000(HIGH!)|r" or ""))
    table.insert(lines, string.format("  Guild Relay:  %s%3d msgs|r %s", queueColor2, #self.guildRelayQueue, #self.guildRelayQueue > 10 and "|cffff0000(HIGH!)|r" or ""))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700THROTTLE SETTINGS|r")
    table.insert(lines, string.format("  BNet/Whisper: %.2fs between msgs", self.SEND_THROTTLE_DELAY))
    table.insert(lines, string.format("  Guild Relay:  %.2fs between msgs", self.GUILD_RELAY_THROTTLE))
    table.insert(lines, string.format("  Roster Sync:  %.0fs between broadcasts", self.ROSTER_SYNC_THROTTLE))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700TRAFFIC|r")
    local bytesPerSec, _ = self:GetBytesPerSecond()
    local bytesColor = bytesPerSec > self.BYTES_WARNING_THRESHOLD and "|cffff0000" or (bytesPerSec > self.BYTES_THROTTLE_THRESHOLD and "|cffff8800" or "|cff00ff00")
    local isDataThrottled = bytesPerSec > self.BYTES_THROTTLE_THRESHOLD

    local throttleMode
    if self:IsInZoneTransition() then
        throttleMode = "|cffff0000PAUSED|r"
    elseif isDataThrottled then
        throttleMode = "|cffff8800DATA THROTTLE|r"
    else
        throttleMode = "|cff00ff00NORMAL|r"
    end

    local currentDelay = self:GetCurrentThrottleDelay()
    table.insert(lines, string.format("  Mode:       %s (%.1fs delay)", throttleMode, currentDelay))
    table.insert(lines, string.format("  Data Rate:  %s%.0f B/s|r (throttle: %d, warn: %d)", bytesColor, bytesPerSec, self.BYTES_THROTTLE_THRESHOLD, self.BYTES_WARNING_THRESHOLD))
    table.insert(lines, string.format("  Total Sent: %d bytes", self.trafficStats.bytesOut))
    table.insert(lines, "")

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myMDGAName = self:GetMDGAName(myGuildClubId) or "Not Allowed"
    local myGuildName = GetGuildInfo("player") or "No Guild"

    table.insert(lines, "|cffffd700MY GUILD|r")
    table.insert(lines, string.format("  Name: %s", myGuildName))
    table.insert(lines, string.format("  ID:   %s", myGuildClubId and tostring(myGuildClubId) or "None"))
    table.insert(lines, string.format("  MDGA: %s", myMDGAName))
    local isAllowed = myGuildClubId and self:IsAllowedGuildId(myGuildClubId)
    table.insert(lines, string.format("  Allowed: %s", isAllowed and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    table.insert(lines, "")

    table.insert(lines, "|cffffd700ALLOWED GUILD IDS|r")
    for guildId, info in pairs(self.allowedGuildIds) do
        local matchIndicator = (myGuildClubId and tostring(myGuildClubId) == guildId) and " |cff00ff00<-- YOU|r" or ""
        table.insert(lines, string.format("  %s: %s (%s)%s", info.name, guildId, info.realm, matchIndicator))
    end
    table.insert(lines, "")

    table.insert(lines, "|cffffd700CONNECTIONS|r")
    table.insert(lines, string.format("  BNet Friends: %d", bnetCount))
    table.insert(lines, string.format("  Whisper Alts: %d", altCount))
    table.insert(lines, "")

    if bnetCount > 0 then
        table.insert(lines, "|cffffd700BNET BRIDGE CONNECTIONS|r")
        for gameAccountID, info in pairs(self.connectedBridgeUsers) do
            local charName = info.characterName or "Unknown"
            local theirGuildId = info.guildClubId and tostring(info.guildClubId) or "None"
            local theirMDGAName = self:GetMDGAName(info.guildClubId) or "Not Allowed"
            local theirGuildName = info.guildName or "Unknown"
            local theirAllowed = info.guildClubId and self:IsAllowedGuildId(info.guildClubId)
            table.insert(lines, string.format("  %s <-> %s via %s", myMDGAName, theirMDGAName, charName))
            table.insert(lines, string.format("    Guild: %s | ID: %s", theirGuildName, theirGuildId))
            table.insert(lines, string.format("    Allowed: %s", theirAllowed and "|cff00ff00YES|r" or "|cffff0000NO|r"))
        end
        table.insert(lines, "")
    end

    if altCount > 0 then
        table.insert(lines, "|cffffd700WHISPER ALT CONNECTIONS|r")
        for altName, info in pairs(self.connectedWhisperAlts) do
            local theirGuildId = info.guildClubId and tostring(info.guildClubId) or "None"
            local theirMDGAName = self:GetMDGAName(info.guildClubId) or "Not Allowed"
            local theirGuildName = info.guildName or "Unknown"
            local theirAllowed = info.guildClubId and self:IsAllowedGuildId(info.guildClubId)
            table.insert(lines, string.format("  %s <-> %s via %s", myMDGAName, theirMDGAName, altName))
            table.insert(lines, string.format("    Guild: %s | ID: %s", theirGuildName, theirGuildId))
            table.insert(lines, string.format("    Allowed: %s", theirAllowed and "|cff00ff00YES|r" or "|cffff0000NO|r"))
        end
        table.insert(lines, "")
    end

    local relayCount = 0
    for _ in pairs(self.guildRelayBridges) do
        relayCount = relayCount + 1
    end
    if relayCount > 0 then
        table.insert(lines, "|cffffd700GUILD RELAY BRIDGES|r")
        table.insert(lines, "  |cff888888(Guildmates relaying cross-guild data to you)|r")
        for senderName, info in pairs(self.guildRelayBridges) do
            local guildsList = {}
            for guildClubId, _ in pairs(info.guilds) do
                local mdgaName = self:GetMDGAName(guildClubId)
                local idStr = tostring(guildClubId)
                if mdgaName then
                    table.insert(guildsList, string.format("%s (ID:%s)", mdgaName, idStr))
                else
                    local guildName = "Unknown"
                    for filterKey, guildInfo in pairs(self.knownGuilds) do
                        if tostring(guildInfo.guildClubId) == idStr then
                            guildName = guildInfo.guildName or "Unknown"
                            break
                        end
                    end
                    table.insert(guildsList, string.format("%s (ID:%s)|cffff0000*|r", guildName, idStr))
                end
            end
            local guildsStr = table.concat(guildsList, ", ")
            table.insert(lines, string.format("  %s relaying <%s>", senderName, guildsStr))
        end
        table.insert(lines, "")
    end

    table.insert(lines, "|cffffd700FEATURES|r")
    local bridgeStatus = MNetDB.bridgeEnabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local relayStatus = MNetDB.enableGuildRelay and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local rosterRelayStatus = MNetDB.relayRosterToGuild and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local trafficStatus = self.enableTrafficDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r"

    table.insert(lines, string.format("  Bridge:              %s", bridgeStatus))
    table.insert(lines, string.format("  Guild Relay:         %s", relayStatus))
    table.insert(lines, string.format("  Roster Relay (Guild):%s", rosterRelayStatus))
    table.insert(lines, string.format("  Party Indicators:    %s", "|cff00ff00LOCAL-ONLY|r"))
    table.insert(lines, string.format("  Traffic Debug:       %s", trafficStatus))

    local partySize = GetNumGroupMembers()
    if partySize > 0 then
        table.insert(lines, "")
        table.insert(lines, string.format("|cffffd700PARTY/RAID SIZE:|r %d members (local tracking only)", partySize))
    end

    table.insert(lines, "")
    table.insert(lines, "|cff888888Commands: /mn traffic (enable chat logging) | /mn stats (show stats) | /mn help (all commands)|r")
    table.insert(lines, "|cff888888Auto-updates every second|r")

    local text = table.concat(lines, "\n")
    self.debugEditBox._lastText = text
    self.debugEditBox._settingText = true
    self.debugEditBox:SetText(text)
    self.debugEditBox._settingText = false

    local numLines = #lines
    local lineHeight = select(2, self.debugEditBox:GetFont()) or 12
    local textHeight = numLines * (lineHeight + 2) + 20
    self.debugEditBox:SetHeight(math.max(textHeight, self.debugScrollFrame:GetHeight()))

    local scrollRange = math.max(0, textHeight - self.debugScrollFrame:GetHeight())
    self.debugScrollBar:SetMinMaxValues(0, scrollRange)

    if scrollRange <= 0 then
        self.debugScrollBar:Hide()
        self.debugScrollFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    else
        self.debugScrollBar:Show()
        self.debugScrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)
    end
end
