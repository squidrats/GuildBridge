# Testing Patterns

**Analysis Date:** 2026-01-17

## Test Framework

**Runner:**
- No automated test framework detected
- No test files found (`*test*`, `*spec*`)

**Assertion Library:**
- Not applicable

**Run Commands:**
- Not applicable - no automated tests exist

## Test File Organization

**Location:**
- No test files present in codebase

**Naming:**
- Not established

**Structure:**
- Not established

## Manual Testing Approach

The codebase relies on manual in-game testing with debug tools:

### Debug Commands

**Traffic Debugging:**
```
/mn traffic    -- Toggle real-time traffic stats in chat
/mn stats      -- Show traffic statistics summary
```

**Event Debugging:**
```
/mn events     -- Toggle event logging (zone changes, connect/disconnect)
```

**Disconnect Debugging:**
```
/mndclog on    -- Enable persistent DC logging (survives disconnects)
/mndclog show  -- Show recent log entries
/mndclog copy  -- Open copyable log window
/mndclog clear -- Clear the log
```

**Status Inspection:**
```
/mn debug      -- Show debug info (guild, connections, queue)
/mn relaystatus -- Show relay election status
/mndebug       -- Global debug command
```

### Debug Output Patterns

**Traffic Debug:**
```lua
if GB.enableTrafficDebug then
    print(string.format("|cff00ff00[Traffic]|r BNet %s (queue: %d)", msgType, #GB.outgoingQueue))
end
```

**Event Debug:**
```lua
if GB.enableEventDebug then
    print("|cffff8800[Event]|r PLAYER_ENTERING_WORLD isLogin=" .. tostring(isLogin))
end
```

**Persistent DC Logging:**
```lua
GB:LogDC("SEND", "BNet " .. msgType .. " to " .. tostring(msg.target) .. " size:" .. #msg.payload)
```

## Mock Patterns

**Framework:** None

**Patterns:**
- No mocking infrastructure
- Tests rely on live WoW environment

**What to Mock (if tests were added):**
- WoW API functions (`C_BattleNet.*`, `GetGuildInfo()`, etc.)
- Event system (`CreateFrame`, `RegisterEvent`)
- Timer functions (`C_Timer.After`, `C_Timer.NewTicker`)
- Network functions (`BNSendGameData`, `C_ChatInfo.SendAddonMessage`)

## Fixtures and Factories

**Test Data:**
- Not applicable

**Location:**
- Not applicable

## Coverage

**Requirements:** None enforced

**View Coverage:**
- Not applicable

## Test Types

**Unit Tests:**
- None present
- Would benefit from testing:
  - Message parsing/serialization (`buildBridgePayload`, `HandleBNAddonMessage`)
  - Hash/deduplication logic (`MakeMessageHash`, `IsDuplicateMessage`)
  - Guild filtering logic (`IsAllowedGuildId`, `IsAllowedGuildIdAndRealm`)

**Integration Tests:**
- None present
- Manual verification in-game

**E2E Tests:**
- None present
- Manual multi-character testing required

## Common Testing Scenarios

**Manual Test Checklist:**

1. **Basic Connectivity:**
   - Log in with addon enabled
   - Verify handshake sent to BNet friends
   - Check `/mn debug` for connections

2. **Cross-Guild Messaging:**
   - Send message from character in Guild A
   - Verify receipt on character in Guild B
   - Check message appears in both native chat and MNet window

3. **Zone Transition Safety:**
   - Enable `/mndclog on`
   - Change zones repeatedly
   - Verify no disconnects
   - Check DC log for paused queue messages

4. **Roster Sync:**
   - Check roster panel shows online members
   - Verify members from connected guilds appear
   - Test filtering by guild tab

5. **Relay Election:**
   - Have multiple characters with connections to same guild
   - Check `/mn relaystatus` to verify PRIMARY selection
   - Verify only PRIMARY relays messages

## Recommendations for Adding Tests

**WoW Addon Testing Options:**

1. **WoWUnit** - Lua testing framework for WoW addons
2. **Busted** - General Lua testing framework (requires mock layer)
3. **Custom mock layer** - Stub WoW APIs for unit testing

**Priority Areas to Test:**

1. `Utils.lua` - Pure functions, easy to unit test
   - `CountTable()`
   - `MakeMessageHash()`
   - `IsDuplicateMessage()`

2. `Core.lua` - State management logic
   - `IsAllowedGuildId()`
   - `MakeFilterKey()`
   - `IsInZoneTransition()`

3. `RosterSync.lua` - Roster serialization
   - `ChunkRosterData()`
   - `AbbrevClass()` / `ExpandClassAbbrev()`
   - `AssembleAndApplyRoster()`

4. `Messages.lua` - Message parsing
   - `buildBridgePayload()` (local, would need refactoring)
   - Payload parsing in `HandleBNAddonMessage()`

---

*Testing analysis: 2026-01-17*
