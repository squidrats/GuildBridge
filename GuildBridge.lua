local addonName = ...
local bridgePayloadPrefix = "[GB]"
local bridgeAddonPrefix = "GuildBridge"

local mainFrame
local scrollFrame
local inputBox
local tabButtons = {}
local muteCheckbox

local eventFrame = CreateFrame("Frame")

-- Current filter: nil = All, or guild-realm key
local currentFilter = nil
-- Store messages for filtering
local messageHistory = {}
-- Track unique guild+realm combinations we've seen
local knownGuilds = {}

-- Message deduplication
local recentMessages = {}  -- Hash -> timestamp
local MESSAGE_DEDUPE_WINDOW = 10  -- seconds

-- Track online friends
local onlineFriends = {}

local guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
    ["Bestiez"] = "Bestiez",
}

-- Only relay messages from these guilds
local allowedGuilds = {
    ["MAKE ELWYNN GREAT AGAIN"] = true,
    ["MAKE DUROTAR GREAT AGAIN"] = true,
    ["Bestiez"] = true,
}

local function ensureSavedVariables()
    if not GuildBridgeDB then
        GuildBridgeDB = {}
    end
    if GuildBridgeDB.bridgeEnabled == nil then
        GuildBridgeDB.bridgeEnabled = true
    end
    if GuildBridgeDB.muteSend == nil then
        GuildBridgeDB.muteSend = false
    end
    if GuildBridgeDB.knownGuilds == nil then
        GuildBridgeDB.knownGuilds = {}
    end
    knownGuilds = GuildBridgeDB.knownGuilds
end

-- Generate a hash for message deduplication
local function makeMessageHash(guildName, originName, originRealm, messageText)
    return guildName .. "|" .. originName .. "|" .. originRealm .. "|" .. messageText
end

-- Check if message is a duplicate (seen recently)
local function isDuplicateMessage(hash)
    local now = GetTime()
    -- Clean old entries
    for h, timestamp in pairs(recentMessages) do
        if now - timestamp > MESSAGE_DEDUPE_WINDOW then
            recentMessages[h] = nil
        end
    end
    -- Check if this hash exists
    if recentMessages[hash] then
        return true
    end
    -- Record this message
    recentMessages[hash] = now
    return false
end

-- Find all online WoW friends
local function findOnlineWoWFriends()
    local friends = {}

    local numFriends = BNGetNumFriends()
    if not numFriends or numFriends == 0 then
        return friends
    end

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGames = C_BattleNet.GetFriendNumGameAccounts(i)
            if numGames and numGames > 0 then
                for j = 1, numGames do
                    local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" then
                        table.insert(friends, {
                            gameAccountID = gameInfo.gameAccountID,
                            characterName = gameInfo.characterName,
                            realmName = gameInfo.realmName,
                            battleTag = accountInfo.battleTag,
                        })
                    end
                end
            end
        end
    end

    return friends
end

-- Forward declarations
local updateConnectionIndicators
local refreshMessages

-- Update list of online friends
local function updateOnlineFriends()
    onlineFriends = findOnlineWoWFriends()

    -- Update connection indicators on tabs
    if updateConnectionIndicators then
        updateConnectionIndicators()
    end

    -- Refresh status tab if it's currently displayed
    if currentFilter == "STATUS" then
        refreshMessages()
    end
end


-- Create a filter key from guild name and realm
local function makeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

-- Forward declarations
local registerGuild
local rebuildTabs

refreshMessages = function()
    if not scrollFrame then return end
    scrollFrame:Clear()

    -- If Status tab is selected, show online friends
    if currentFilter == "STATUS" then
        scrollFrame:AddMessage("|cff88ffffOnline WoW Friends:|r")
        scrollFrame:AddMessage("")

        if #onlineFriends == 0 then
            scrollFrame:AddMessage("|cffff8888No friends online.|r")
        else
            for _, friend in ipairs(onlineFriends) do
                scrollFrame:AddMessage("  |cff00ff00" .. friend.characterName .. "-" .. (friend.realmName or "") .. "|r")
            end
        end

        scrollFrame:AddMessage("")
        scrollFrame:AddMessage("|cff888888Messages sent to all online friends.|r")
        scrollFrame:AddMessage("|cff888888Only those with addon in allowed guilds will relay.|r")
        return
    end

    -- Normal message display
    for _, msg in ipairs(messageHistory) do
        if currentFilter == nil or msg.filterKey == currentFilter then
            scrollFrame:AddMessage(msg.formatted)
        end
    end
end

local function addBridgeMessage(senderName, guildName, factionTag, messageText, realmName)
    local short = guildShortNames[guildName] or guildName or ""
    local realmSuffix = ""
    if realmName and realmName ~= "" then
        realmSuffix = "-" .. realmName
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

    local fullName = senderName
    if realmName and realmName ~= "" then
        fullName = senderName .. "-" .. realmName
    end
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. senderName .. "]|r|h"

    local formattedMessage = guildTag .. senderLink .. ": " .. messageText
    local filterKey = makeFilterKey(guildName, realmName)

    registerGuild(guildName, realmName)

    table.insert(messageHistory, {
        guildName = guildName,
        realmName = realmName,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, 0.25, 1.0, 0.25)
end

local function sendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm)
    if not messageText or messageText == "" then
        return
    end

    -- Get current online friends
    if #onlineFriends == 0 then
        onlineFriends = findOnlineWoWFriends()
    end

    if #onlineFriends == 0 then
        return
    end

    sourceType = sourceType or "U"

    local guildName = overrideGuild or GetGuildInfo("player")
    local guildRealm = overrideGuildRealm or GetRealmName()
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    -- Generate message ID for deduplication if not provided
    if not messageId or messageId == "" then
        messageId = guildRealm .. "-" .. originName .. "-" .. GetTime()
    end

    local payload = bridgePayloadPrefix
        .. (guildName or "")
        .. "|"
        .. (guildRealm or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. (originRealm or "")
        .. "|"
        .. sourceType
        .. "|"
        .. (targetFilter or "")
        .. "|"
        .. messageId
        .. "|"
        .. messageText

    -- Send to all online WoW friends
    for _, friend in ipairs(onlineFriends) do
        local ok, err = pcall(BNSendGameData, friend.gameAccountID, bridgeAddonPrefix, payload)
        if not ok then
            print("GuildBridge: error sending to", friend.characterName or "unknown", ":", err)
        end
    end
end

local function sendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

    local targetFilter = currentFilter

    local originName, originRealm = UnitName("player")
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end
    local playerGuildName = GetGuildInfo("player")

    local short = guildShortNames[playerGuildName] or playerGuildName or ""
    local realmSuffix = ""
    if originRealm and originRealm ~= "" then
        realmSuffix = "-" .. originRealm
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""
    local fullName = originName .. "-" .. originRealm
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. messageText
    local filterKey = makeFilterKey(playerGuildName, originRealm)

    table.insert(messageHistory, {
        guildName = playerGuildName,
        realmName = originRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    -- Record hash so we don't display it again when it comes back
    local hash = makeMessageHash(playerGuildName or "", originName, originRealm, messageText)
    isDuplicateMessage(hash)  -- This records the hash

    sendBridgePayload(originName, originRealm, messageText, "U", targetFilter)
end


local function handleGuildChatMessage(text, sender)
    if not IsInGuild() then
        return
    end
    if not text or text == "" then
        return
    end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not allowedGuilds[myGuildName] then
        return
    end

    local originName, originRealm = sender:match("([^%-]+)%-?(.*)")
    originName = originName or sender
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end

    local short = guildShortNames[myGuildName] or myGuildName or ""
    local realmSuffix = "-" .. originRealm
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""
    local fullName = originName .. "-" .. originRealm
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. text
    local filterKey = makeFilterKey(myGuildName, originRealm)

    registerGuild(myGuildName, originRealm)
    table.insert(messageHistory, {
        guildName = myGuildName,
        realmName = originRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    if not GuildBridgeDB.bridgeEnabled then
        return
    end

    if GuildBridgeDB.muteSend then
        local myName = UnitName("player")
        if originName == myName then
            return
        end
    end

    -- Check for duplicate before relaying
    local hash = makeMessageHash(myGuildName, originName, originRealm, text)
    if isDuplicateMessage(hash) then
        return
    end

    sendBridgePayload(originName, originRealm, text, "G")
end

local function handleBNAddonMessage(prefix, message, senderID)
    if prefix ~= bridgeAddonPrefix then
        return
    end

    local text = message
    if not text or text:sub(1, #bridgePayloadPrefix) ~= bridgePayloadPrefix then
        return
    end

    local payload = text:sub(#bridgePayloadPrefix + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        messageIdPart = nil
    end

    if not messagePart then
        guildPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildRealmPart = originRealmPart
        messageIdPart = nil
    end

    if not messagePart or not originPart or not sourcePart then
        return
    end

    if guildPart == "" then guildPart = nil end
    if guildRealmPart == "" then guildRealmPart = nil end
    if originRealmPart == "" then originRealmPart = nil end
    if targetPart == "" then targetPart = nil end
    if messageIdPart == "" then messageIdPart = nil end

    -- Only accept messages from allowed guilds
    if guildPart and not allowedGuilds[guildPart] then
        return
    end

    -- Check for duplicate message using hash
    local hash = makeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if isDuplicateMessage(hash) then
        return
    end

    -- If message has a target filter, only process if we match
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myRealm = GetRealmName()
        local myFilterKey = makeFilterKey(myGuildName, myRealm)
        if myFilterKey ~= targetPart then
            return
        end
    end

    -- Display the message
    addBridgeMessage(originPart, guildPart, factionPart, messagePart, guildRealmPart)

    -- Re-relay to other friends (mesh network) - but NOT if this came from guild chat
    -- Only re-relay if sourceType is not "G" (guild originated)
    if GuildBridgeDB.bridgeEnabled and sourcePart ~= "G" then
        sendBridgePayload(originPart, originRealmPart, messagePart, sourcePart, targetPart, messageIdPart, guildPart, guildRealmPart)
    end
end

local function updateTabHighlights()
    for _, tab in pairs(tabButtons) do
        if tab.filterValue == currentFilter then
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

-- Update connection status indicators - just show if we have online friends
updateConnectionIndicators = function()
    local hasOnlineFriends = #onlineFriends > 0
    for _, tab in pairs(tabButtons) do
        if tab.statusDot and tab.guildName then
            if hasOnlineFriends then
                tab.statusDot:SetColorTexture(0.3, 0.8, 0.3, 1)  -- Green
            else
                tab.statusDot:SetColorTexture(0.8, 0.3, 0.3, 1)  -- Red
            end
        end
    end
end

local function forgetGuild(filterKey)
    if not filterKey then return end
    knownGuilds[filterKey] = nil
    GuildBridgeDB.knownGuilds = knownGuilds
    if currentFilter == filterKey then
        currentFilter = nil
    end
    rebuildTabs()
    refreshMessages()
end

local contextMenu
local forgetButton

local function ensureContextMenu()
    if contextMenu then return end

    contextMenu = CreateFrame("Frame", "GuildBridgeContextMenu", UIParent, "BackdropTemplate")
    contextMenu:SetSize(120, 50)
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

    forgetButton = CreateFrame("Button", nil, contextMenu)
    forgetButton:SetSize(110, 20)
    forgetButton:SetPoint("TOP", contextMenu, "TOP", 0, -8)
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
            if not MouseIsOver(self) then
                self:Hide()
            end
        end
    end)
    contextMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

local function showContextMenu(filterKey, guildLabel)
    ensureContextMenu()
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

local function createTab(parent, guildLabel, realmLabel, filterValue, xOffset, guildName)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetSize(72, 34)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -20)
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
        if button == "RightButton" and filterValue then
            showContextMenu(filterValue, guildLabel)
        elseif button == "LeftButton" then
            currentFilter = filterValue
            updateTabHighlights()
            refreshMessages()
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

rebuildTabs = function()
    if not mainFrame then return end

    for key, tab in pairs(tabButtons) do
        tab:Hide()
        tab:SetParent(nil)
    end
    tabButtons = {}

    local xOffset = 8
    local tabSpacing = 4
    tabButtons.all = createTab(mainFrame, "All", nil, nil, xOffset, nil)
    xOffset = xOffset + 72 + tabSpacing

    local myGuildName = GetGuildInfo("player")
    local tabIndex = 1
    for filterKey, info in pairs(knownGuilds) do
        if info.guildName ~= myGuildName then
            local short = guildShortNames[info.guildName] or info.guildName or "?"
            local realmLabel = info.realmName
            tabButtons["guild" .. tabIndex] = createTab(mainFrame, short, realmLabel, filterKey, xOffset, info.guildName)
            xOffset = xOffset + 72 + tabSpacing
            tabIndex = tabIndex + 1
        end
    end

    tabButtons.status = createTab(mainFrame, "Status", nil, "STATUS", xOffset, nil)
    tabButtons.status.isStatusTab = true

    updateTabHighlights()
    updateConnectionIndicators()
end

registerGuild = function(guildName, realmName)
    if not guildName then return end
    local filterKey = makeFilterKey(guildName, realmName)
    if not knownGuilds[filterKey] then
        knownGuilds[filterKey] = {
            guildName = guildName,
            realmName = realmName,
        }
        GuildBridgeDB.knownGuilds = knownGuilds
        rebuildTabs()
    end
end

local function createBridgeUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 300)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Guild Bridge")

    rebuildTabs()

    muteCheckbox = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    muteCheckbox:SetSize(24, 24)
    muteCheckbox:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -22)
    muteCheckbox.text = muteCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    muteCheckbox.text:SetPoint("RIGHT", muteCheckbox, "LEFT", -2, 0)
    muteCheckbox.text:SetText("Mute Send")
    muteCheckbox:SetChecked(GuildBridgeDB.muteSend or false)
    muteCheckbox:SetScript("OnClick", function(self)
        GuildBridgeDB.muteSend = self:GetChecked()
    end)

    scrollFrame = CreateFrame("ScrollingMessageFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    scrollFrame:SetFontObject(GameFontHighlightSmall)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(500)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetHyperlinksEnabled(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        elseif delta < 0 then
            self:ScrollDown()
        end
    end)
    scrollFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button)
    end)

    inputBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    inputBox:SetPoint("BOTTOMLEFT", 10, 10)
    inputBox:SetPoint("BOTTOMRIGHT", -10, 10)
    inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetFontObject(GameFontHighlightSmall)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        sendFromUI(text)
        self:SetText("")
    end)

    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    mainFrame:Hide()
end

local function toggleBridgeFrame()
    if not mainFrame then
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
eventFrame:RegisterEvent("BN_CONNECTED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            ensureSavedVariables()
            C_ChatInfo.RegisterAddonMessagePrefix(bridgeAddonPrefix)
            createBridgeUI()
        end
    elseif event == "PLAYER_LOGIN" or event == "BN_CONNECTED" then
        updateOnlineFriends()
    elseif event == "BN_FRIEND_INFO_CHANGED" then
        updateOnlineFriends()
    elseif event == "CHAT_MSG_GUILD" then
        local text, sender = ...
        handleGuildChatMessage(text, sender)
    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, _, senderID = ...
        handleBNAddonMessage(prefix, message, senderID)
    end
end)

SLASH_GUILDBRIDGE1 = "/gbridge"
SLASH_GUILDBRIDGE2 = "/gb"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    msg = msg or ""
    msg = msg:lower()

    if msg == "" or msg == "show" then
        toggleBridgeFrame()
    elseif msg == "status" then
        ensureSavedVariables()
        print("GuildBridge: Online WoW friends (" .. #onlineFriends .. "):")
        for _, friend in ipairs(onlineFriends) do
            print("  |cff00ff00" .. friend.characterName .. "-" .. (friend.realmName or "") .. "|r")
        end
        if #onlineFriends == 0 then
            print("  No friends online.")
        end
    elseif msg == "reload" or msg == "refresh" then
        ensureSavedVariables()
        updateOnlineFriends()
        print("GuildBridge: Friend list refreshed. " .. #onlineFriends .. " online.")
    else
        print("GuildBridge commands:")
        print("  /gb - Toggle bridge window")
        print("  /gbridge status - Show online friends")
        print("  /gbridge reload - Refresh friend list")
    end
end
