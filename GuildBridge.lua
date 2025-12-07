local addonName = ...
local bridgePayloadPrefix = "[GB]"
local bridgeMarkerInGuild = "[Bridge]"
local bridgeCommunityName = "GuildBridge"
local bridgeStreamName = "Bridge"

local bridgeClubId
local bridgeStreamId

local mainFrame
local scrollFrame
local inputBox

local eventFrame = CreateFrame("Frame")

local function ensureSavedVariables()
    if not GuildBridgeDB then
        GuildBridgeDB = {}
    end
    if GuildBridgeDB.bridgeEnabled == nil then
        GuildBridgeDB.bridgeEnabled = false
    end
end

local function findBridgeClubAndStream()
    local clubs = C_Club.GetSubscribedClubs()
    if not clubs then
        return false
    end

    for _, club in ipairs(clubs) do
        if club.name == bridgeCommunityName then
            bridgeClubId = club.clubId
            local streams = C_Club.GetStreams(bridgeClubId)
            if not streams then
                return false
            end
            for _, stream in ipairs(streams) do
                if stream.name == bridgeStreamName then
                    bridgeStreamId = stream.streamId
                    return true
                end
            end
        end
    end

    return false
end

local function addBridgeMessage(senderName, guildName, factionTag, messageText)
    if not scrollFrame then
        return
    end

    local factionString = factionTag and factionTag ~= "" and ("[" .. factionTag .. "] ") or ""
    local guildTag = guildName and guildName ~= "" and ("<" .. guildName .. "> ") or ""
    local senderColored = "|cff00ff00" .. senderName .. "|r"

    scrollFrame:AddMessage(factionString .. guildTag .. senderColored .. ": " .. messageText)
end

local function sendCommunityPayload(originName, messageText, sourceType)
    if not bridgeClubId or not bridgeStreamId then
        return
    end
    if not messageText or messageText == "" then
        return
    end
    sourceType = sourceType or "U"

    local playerGuildName = GetGuildInfo("player")
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    local payload = bridgePayloadPrefix
        .. (playerGuildName or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. sourceType
        .. "|"
        .. messageText

    C_Club.SendMessage(bridgeClubId, bridgeStreamId, payload)
end

local function sendCommunityFromUI(messageText)
    local originName = UnitName("player")
    sendCommunityPayload(originName, messageText, "U")
end

local function mirrorToGuild(senderName, guildName, factionTag, messageText, sourceType)
    if not GuildBridgeDB.bridgeEnabled then
        return
    end
    if not IsInGuild() then
        return
    end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName then
        return
    end

    if sourceType == "G" and guildName == myGuildName then
        return
    end

    local factionString = factionTag and factionTag ~= "" and ("[" .. factionTag .. "] ") or ""
    local guildTag = guildName and guildName ~= "" and ("<" .. guildName .. "> ") or ""
    local line = bridgeMarkerInGuild .. " " .. factionString .. guildTag .. senderName .. ": " .. messageText

    SendChatMessage(line, "GUILD")
end

local function handleGuildChatMessage(text, sender)
    if not GuildBridgeDB.bridgeEnabled then
        return
    end
    if not IsInGuild() then
        return
    end
    if not bridgeClubId or not bridgeStreamId then
        return
    end
    if not text or text == "" then
        return
    end
    if text:sub(1, #bridgeMarkerInGuild) == bridgeMarkerInGuild then
        return
    end

    local originName = sender:match("([^%-]+)") or sender
    sendCommunityPayload(originName, text, "G")
end

local function createBridgeUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 260)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Guild Bridge")

    scrollFrame = CreateFrame("ScrollingMessageFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    scrollFrame:SetFontObject(GameFontHighlightSmall)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(500)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        elseif delta < 0 then
            self:ScrollDown()
        end
    end)

    inputBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    inputBox:SetPoint("BOTTOMLEFT", 10, 10)
    inputBox:SetPoint("BOTTOMRIGHT", -10, 10)
    inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetFontObject(GameFontHighlightSmall)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        sendCommunityFromUI(text)
        self:SetText("")
    end)

    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
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
eventFrame:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            ensureSavedVariables()
            createBridgeUI()
        end
    elseif event == "PLAYER_LOGIN" then
        findBridgeClubAndStream()
    elseif event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        local text, _, _, _, _, _, _, _, _, _, _, _, _, clubId, streamId = ...
        if clubId ~= bridgeClubId or streamId ~= bridgeStreamId then
            return
        end
        if not text or text:sub(1, #bridgePayloadPrefix) ~= bridgePayloadPrefix then
            return
        end

        local payload = text:sub(#bridgePayloadPrefix + 1)
        local guildPart, factionPart, originPart, sourcePart, messagePart = payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        if not messagePart or not originPart or not sourcePart then
            return
        end

        if guildPart == "" then
            guildPart = nil
        end

        addBridgeMessage(originPart, guildPart, factionPart, messagePart)
        mirrorToGuild(originPart, guildPart, factionPart, messagePart, sourcePart)
    elseif event == "CHAT_MSG_GUILD" then
        local text, sender = ...
        handleGuildChatMessage(text, sender)
    end
end)

SLASH_GUILDBRIDGE1 = "/gbridge"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    msg = msg or ""
    msg = msg:lower()

    if msg == "" or msg == "show" then
        toggleBridgeFrame()
    elseif msg == "enable" then
        ensureSavedVariables()
        GuildBridgeDB.bridgeEnabled = true
        print("GuildBridge: mirroring enabled on this character.")
    elseif msg == "disable" then
        ensureSavedVariables()
        GuildBridgeDB.bridgeEnabled = false
        print("GuildBridge: mirroring disabled on this character.")
    elseif msg == "status" then
        ensureSavedVariables()
        local status = GuildBridgeDB.bridgeEnabled and "enabled" or "disabled"
        print("GuildBridge: mirroring is " .. status .. " on this character.")
    elseif msg == "reload" then
        findBridgeClubAndStream()
        print("GuildBridge: community info refreshed.")
    else
        print("GuildBridge: /gbridge, /gbridge show, /gbridge enable, /gbridge disable, /gbridge status, /gbridge reload")
    end
end
