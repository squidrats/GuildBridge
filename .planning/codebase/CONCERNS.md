# Codebase Concerns

**Analysis Date:** 2026-01-17

## Tech Debt

**Duplicated Message Parsing Logic:**
- Issue: Identical payload parsing regex patterns are copy-pasted across multiple functions
- Files: `Messages.lua:521-555`, `Messages.lua:678-707`, `Messages.lua:1032-1059`
- Impact: Bug fixes or protocol changes require updating 3+ locations; easy to miss one
- Fix approach: Extract payload parsing into a single `ParseBridgePayload(payload)` function that returns a structured table

**Hardcoded Guild IDs and Names:**
- Issue: Guild allowlist and display names are hardcoded in `Core.lua` rather than configurable
- Files: `Core.lua:95-110` (`guildShortNames`, `guildNumbers`, `allowedGuildIds`)
- Impact: Adding/removing guilds requires code changes instead of configuration
- Fix approach: Move allowlist to SavedVariables with a UI for management, or use a server-side configuration

**Fallback Pattern Matching in Payload Parsing:**
- Issue: Multiple nested fallback patterns for backward compatibility with old message formats
- Files: `Messages.lua:521-555`, `Messages.lua:678-707`
- Impact: Increases code complexity; difficult to reason about which format is actually in use
- Fix approach: Version the protocol explicitly; deprecate old formats after transition period

**Inline UI Construction:**
- Issue: `UI.lua` (2100+ lines) builds entire UI programmatically in one massive function
- Files: `UI.lua:1282-1999` (`CreateBridgeUI`)
- Impact: Difficult to maintain; hard to find specific UI elements; mixing layout with logic
- Fix approach: Break into smaller functions per UI section (titlebar, tabs, roster panel, chat area)

**Global Namespace Pollution:**
- Issue: Addon uses `GB` as internal namespace but also exposes `MNet = GB` globally
- Files: `Core.lua:3`
- Impact: Potential conflicts with other addons; no encapsulation
- Fix approach: Keep internal API private; expose only needed functions via explicit public API

## Known Bugs

**Empty Return Statement with Side Effects:**
- Symptoms: Code path silently ignored without logging
- Files: `Messages.lua:287-288` (empty `else` block after `if not info.guildClubId...`)
- Trigger: When whisper alt has no guildClubId
- Workaround: None currently; messages silently dropped

**Roster Delta Count Mismatch Recovery:**
- Symptoms: Roster may request full refresh unnecessarily
- Files: `RosterSync.lua:609-642`
- Trigger: When count difference > 5, triggers full roster request even if delta would have been correct
- Workaround: Threshold of 5 is arbitrary; may cause extra network traffic

## Security Considerations

**No Message Authentication:**
- Risk: Spoofed messages could be injected via BNet or addon whispers if attacker knows protocol
- Files: `Messages.lua`, `Handshake.lua`
- Current mitigation: Guild ID allowlist (`Core.lua:106-110`) checks against hardcoded list
- Recommendations: Consider adding message signing for critical operations; currently relies on BNet/Blizzard channel security

**Persistent DC Logging Contains User Data:**
- Risk: DC log stores character names, realms, timestamps in SavedVariables
- Files: `Core.lua:214-234` (`LogDC` function)
- Current mitigation: Limited to 2000 entries; only stored locally
- Recommendations: Add option to disable; consider anonymizing character names in logs

**Unbounded SavedVariables Growth:**
- Risk: `knownGuilds` and `registeredAlts` can grow indefinitely
- Files: `Core.lua:186-191`
- Current mitigation: Users can manually "forget" guilds via UI
- Recommendations: Add automatic cleanup of stale guild entries

## Performance Bottlenecks

**Full Guild Roster Iteration on Every Class Color Lookup:**
- Problem: `GetClassColor` iterates entire guild roster for each lookup
- Files: `Utils.lua:182-204`
- Cause: No caching of class colors; called per-message rendering
- Improvement path: Cache class colors in roster data; invalidate on roster update

**BNet Friend List Scanned Multiple Times:**
- Problem: `FindOnlineWoWFriends` iterates all friends and game accounts
- Files: `Utils.lua:29-100`
- Cause: Called on every friend status change event
- Improvement path: Already has 5-second throttle; consider incremental updates instead of full scan

**UI Tab Rebuild on Window Resize:**
- Problem: All tabs destroyed and recreated on resize
- Files: `UI.lua:1198-1280` (`RebuildTabs`)
- Cause: Full rebuild instead of repositioning existing tabs
- Improvement path: Reposition existing tabs; only rebuild on guild list changes

**Roster Panel Entries Recreated Each Refresh:**
- Problem: Roster entries shown/hidden but recreated if more than previous max
- Files: `UI.lua:135-392` (`RefreshRoster`)
- Cause: Entry pool grows but never shrinks; entries recreated per refresh
- Improvement path: Use fixed entry pool; recycle entries instead of hiding

## Fragile Areas

**Zone Transition Detection:**
- Files: `Core.lua:18-21`, `Events.lua:89-106`, `Events.lua:478-485`
- Why fragile: 8-second hardcoded cooldown (`ZONE_TRANSITION_COOLDOWN`) is arbitrary; may be too short for slow loads or too long for fast transitions
- Safe modification: Test thoroughly with slow hardware; consider dynamic detection based on loading screen events
- Test coverage: Manual testing only; no automated tests

**Relay Election System:**
- Files: `Core.lua:523-554` (`AmIPrimaryRelayForGuild`)
- Why fragile: Relies on alphabetical sorting of player names; race conditions possible if multiple players process messages simultaneously
- Safe modification: Add versioning or timestamps to election; consider explicit coordinator announcement
- Test coverage: None; relies on manual testing with multiple accounts

**Message Deduplication:**
- Files: `Utils.lua:15-27` (`IsDuplicateMessage`)
- Why fragile: Uses 10-second window (`MESSAGE_DEDUPE_WINDOW`); hash collision on similar messages possible
- Safe modification: Include timestamp or sequence number in hash
- Test coverage: None

**Queue Processing During Zone Transitions:**
- Files: `Core.lua:402-471` (`ProcessQueue`), `Messages.lua:964-1016` (`ProcessGuildRelayQueue`)
- Why fragile: Pauses but does not clear queue; resumed after cooldown which may cause burst
- Safe modification: Consider dropping non-critical messages during long transitions
- Test coverage: None; added after disconnect issues

## Scaling Limits

**Message History:**
- Current capacity: 500 messages per session (`Messages.lua:133-135`)
- Limit: Memory grows linearly; no persistence across sessions
- Scaling path: Consider pagination or virtual scrolling; persist to SavedVariables with size limit

**Outgoing Queue:**
- Current capacity: Unbounded (`Core.lua:36` `outgoingQueue = {}`)
- Limit: High-traffic situations (raids, events) can cause queue backlog
- Scaling path: Add queue size limit; drop lowest-priority messages when full

**DC Log:**
- Current capacity: 2000 entries (`Core.lua:230-232`)
- Limit: May fill quickly during debug sessions
- Scaling path: Current limit is reasonable; consider log rotation

**Guild Relay Queue:**
- Current capacity: Unbounded (`Core.lua:62` `guildRelayQueue = {}`)
- Limit: 4-second throttle between sends (`GUILD_RELAY_THROTTLE`)
- Scaling path: During high traffic, queue can grow; add size limit similar to outgoing queue

## Dependencies at Risk

**C_Club API:**
- Risk: WoW API changes could break guild club ID retrieval
- Impact: Core functionality depends on `C_Club.GetGuildClubId()`
- Migration plan: Wrap in compatibility layer; already uses `C_Club and C_Club.GetGuildClubId` guards

**BNet API:**
- Risk: Battle.net API changes could break friend detection
- Impact: `BNGetNumFriends`, `C_BattleNet.GetFriendAccountInfo` used extensively
- Migration plan: All calls wrapped in pcall; fallback behavior defined

## Missing Critical Features

**Error Recovery UI:**
- Problem: When disconnects occur, no user feedback about queue state or recovery
- Blocks: Users cannot diagnose connection issues without debug commands

**Rate Limit Visibility:**
- Problem: No indication when message throttling is active
- Blocks: Users may think messages are lost when actually queued

**Connection Health Indicator:**
- Problem: Status page shows connections but not health (latency, message success rate)
- Blocks: Proactive troubleshooting of connection issues

## Test Coverage Gaps

**No Automated Tests:**
- What's not tested: Entire codebase has zero automated tests
- Files: All Lua files
- Risk: Regressions go unnoticed; manual testing required for every change
- Priority: High - consider adding Busted/LuaUnit test framework

**Message Protocol Parsing:**
- What's not tested: Payload parsing with various field combinations
- Files: `Messages.lua:521-555`
- Risk: Protocol changes or edge cases may break parsing silently
- Priority: High - most complex parsing logic

**Queue Behavior Under Load:**
- What's not tested: Queue behavior when messages arrive faster than send rate
- Files: `Core.lua:402-471`, `Messages.lua:964-1016`
- Risk: Potential message loss or memory issues during high traffic
- Priority: Medium - impacts user experience during raids

**Zone Transition Handling:**
- What's not tested: Behavior during rapid zone changes, loading screens, disconnects
- Files: `Events.lua:89-106`, `Core.lua:18-21`
- Risk: The primary source of user-reported disconnects
- Priority: High - directly impacts stability

---

*Concerns audit: 2026-01-17*
