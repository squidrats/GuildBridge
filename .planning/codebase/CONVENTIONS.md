# Coding Conventions

**Analysis Date:** 2026-01-17

## Naming Patterns

**Files:**
- PascalCase for Lua files: `Core.lua`, `Messages.lua`, `RosterSync.lua`
- All source files are `.lua` extension
- One primary module per file

**Functions:**
- Methods on the GB namespace use PascalCase: `GB:SendBridgePayload()`, `GB:HandleHandshakeMessage()`
- Local helper functions use camelCase: `doSendHandshake()`, `lookupCharacterName()`, `buildBridgePayload()`
- Boolean-returning functions use `Is`/`Has` prefix: `GB:IsAllowedGuildId()`, `GB:HasConnectionToGuild()`
- Action functions use verb prefix: `GB:Send*()`, `GB:Handle*()`, `GB:Process*()`, `GB:Queue*()`

**Variables:**
- Local variables use camelCase: `myGuildName`, `filterKey`, `guildClubId`
- Constants use SCREAMING_SNAKE_CASE: `GB.BRIDGE_PAYLOAD_PREFIX`, `GB.MESSAGE_DEDUPE_WINDOW`
- Table keys use camelCase: `guildName`, `guildHomeRealm`, `lastSeen`
- Loop iterators use short names: `i`, `j`, `_` for unused

**Types/Tables:**
- Main addon namespace is `GB` (GuildBridge)
- Exposed globally as `MNet = GB`
- SavedVariables table is `MNetDB`

## Code Style

**Formatting:**
- No automated formatter detected
- 4-space indentation
- No trailing whitespace
- Single blank lines between function definitions

**Linting:**
- No linting configuration detected
- Code relies on WoW API globals without explicit declaration

## Import Organization

**Order:**
1. Addon namespace unpacking: `local addonName, GB = ...`
2. Local constant definitions
3. Local helper functions
4. GB method definitions

**Module Loading:**
- Load order defined in `MNet.toc`:
  1. `Core.lua` - Constants, state, queue management
  2. `Utils.lua` - Helper functions
  3. `Handshake.lua` - Connection handshaking
  4. `Messages.lua` - Message handling/routing
  5. `RosterSync.lua` - Guild roster synchronization
  6. `UI.lua` - User interface
  7. `Events.lua` - Event handlers
  8. `Commands.lua` - Slash commands

## Error Handling

**Patterns:**
- Early return for nil/invalid input:
  ```lua
  if not guildName then return nil end
  if not messageText or messageText == "" then return end
  ```
- Use `pcall()` for WoW API calls that may fail:
  ```lua
  local success, numFriends = pcall(BNGetNumFriends)
  if not success or not numFriends then return friends end
  ```
- Defensive nil checks before table access:
  ```lua
  if info.guildClubId and tostring(info.guildClubId) == guildClubIdStr then
  ```

**Error Recovery:**
- Silent failures preferred over errors
- Debug output via conditional `enableEventDebug` and `enableTrafficDebug` flags
- Persistent logging via `GB:LogDC()` for disconnect debugging

## Logging

**Framework:** Custom logging via `GB:LogDC()` and conditional prints

**Patterns:**
- Debug output controlled by flags:
  ```lua
  if GB.enableEventDebug then
      print("|cffff8800[Event]|r PLAYER_ENTERING_WORLD isLogin=" .. tostring(isLogin))
  end
  ```
- Color-coded prefixes for different log types:
  - `|cff00ff00[MNet]|r` - Green for info
  - `|cffff8800[Event]|r` - Orange for events
  - `|cff888888` - Gray for debug details
- Persistent DC logging for crash debugging:
  ```lua
  GB:LogDC("SEND", "BNet " .. msgType .. " to " .. tostring(msg.target))
  ```

## Comments

**When to Comment:**
- Explain "why" for non-obvious logic
- Warn about potential issues (e.g., `-- Skip sending during zone transitions to prevent D/C`)
- Mark sections with `-- Protect against seamless zone transitions`

**JSDoc/TSDoc:**
- Not used (Lua has no standard documentation format)
- No inline type annotations

## Function Design

**Size:**
- Functions vary widely (5-150 lines)
- Complex message handlers are long but linear
- UI code tends to be longest

**Parameters:**
- Optional parameters default to nil
- Parameter validation at function start
- Many parameters for payload builders (11+ params in `buildBridgePayload`)

**Return Values:**
- Return `nil` or nothing on failure
- Return `true` for handled messages, `false` for unhandled
- Return data directly (no wrapper objects)

## Module Design

**Exports:**
- All public functions attached to `GB` namespace
- No separate export table
- File-private helpers via `local function`

**Barrel Files:**
- Not used; `.toc` file controls load order

## WoW-Specific Patterns

**Event Frame Pattern:**
```lua
GB.eventFrame = CreateFrame("Frame")
GB.eventFrame:RegisterEvent("ADDON_LOADED")
GB.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        -- handle
    end
end)
```

**Slash Command Registration:**
```lua
SLASH_MDGANET1 = "/mn"
SLASH_MDGANET2 = "/mdganet"
SlashCmdList["MDGANET"] = function(msg)
    -- handle
end
```

**Timer/Debounce Pattern:**
```lua
C_Timer.After(delay, function()
    if GB:IsInZoneTransition() then return end
    -- execute
end)
```

**Message Prefix Format:**
- Prefixes are 4-6 char tags in brackets: `[GBHS]`, `[GBRF]`, `[GBRD]`, `[GB]`
- Payload fields separated by `|`

## Anti-Patterns to Avoid

- Do not use `print()` without debug flag check
- Do not call BNet APIs without throttling
- Do not send network messages during zone transitions
- Do not use interactive git flags (-i)

---

*Convention analysis: 2026-01-17*
