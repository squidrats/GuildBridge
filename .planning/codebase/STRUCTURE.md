# Codebase Structure

**Analysis Date:** 2026-01-17

## Directory Layout

```
MNet/
├── Core.lua           # Global state, constants, message queue, relay logic
├── Utils.lua          # Helper functions: deduplication, friend scanning, colors
├── Handshake.lua      # Connection establishment protocol (BNet + Whisper)
├── Messages.lua       # Chat message handling, payload format, relay
├── RosterSync.lua     # Guild roster synchronization protocol
├── UI.lua             # Main window, tabs, roster panel, chat display
├── Events.lua         # WoW event handlers and timer setup
├── Commands.lua       # Slash command handlers (/mn, /mdganet)
├── MNet.toc           # Addon manifest and load order
├── README.md          # Documentation (empty)
└── .planning/         # Planning documents
    └── codebase/      # Codebase analysis documents
```

## Directory Purposes

**Root Directory:**
- Purpose: All addon source files (flat structure, no subdirectories for code)
- Contains: Lua source files, TOC manifest
- Key files: `Core.lua` (state), `Events.lua` (entry), `UI.lua` (interface)

**.planning/codebase:**
- Purpose: GSD codebase analysis documents
- Contains: Architecture and structure documentation
- Generated: By GSD map-codebase command
- Committed: Yes

## Key File Locations

**Entry Points:**
- `MNet.toc`: Addon manifest defining load order
- `Events.lua`: Event registration and handlers (ADDON_LOADED starts everything)

**Configuration:**
- `Core.lua` lines 5-16: Throttle constants and timing values
- `Core.lua` lines 95-110: Hardcoded guild mappings (allowedGuildIds, guildNumbers)
- `MNetDB` (SavedVariable): User preferences stored in WTF folder

**Core Logic:**
- `Core.lua`: Global state tables, queue processors, relay election
- `Messages.lua`: Message payload format, send/receive handlers
- `Handshake.lua`: HELLO/PONG protocol, connection tracking
- `RosterSync.lua`: Roster chunking, delta protocol, member tracking

**User Interface:**
- `UI.lua`: CreateBridgeUI(), RefreshRoster(), tab management

**Commands:**
- `Commands.lua`: SlashCmdList["MDGANET"] handles all /mn subcommands

**Utilities:**
- `Utils.lua`: FindOnlineWoWFriends(), IsDuplicateMessage(), GetClassColor()

## Naming Conventions

**Files:**
- PascalCase for Lua files: `RosterSync.lua`, `Events.lua`
- All-caps with extension for TOC: `MNet.toc`

**Global Objects:**
- `GB`: Local reference to addon table (passed via varargs)
- `MNet`: Global reference (assigned in Core.lua line 3)
- `MNetDB`: SavedVariable for persistent data

**Functions:**
- Methods on GB object: `GB:FunctionName()` (colon notation)
- Local helpers: `local function camelCase()`
- Slash commands: `SLASH_CMDNAME1`, `SlashCmdList["CMDNAME"]`

**Message Prefixes:**
- `[GB]`: Chat message payload
- `[GBHS]`: BNet handshake
- `[GBWHS]`: Whisper handshake
- `[GBRF]`: Roster full
- `[GBRD]`: Roster delta
- `[GBRR]`: Roster request
- `[GBGR]`: Guild relay chat
- `[GBGD]`: Guild relay data
- `[GBRA]`: Relay availability announcement
- `[GBPY]`: Party (deprecated/unused)

## Where to Add New Code

**New Feature (Cross-Guild Communication):**
- Primary code: `Messages.lua` for new message types
- Protocol handler: Add handler in `HandleBNAddonMessage()` / `HandleWhisperAddonMessage()`
- State tracking: Add tables to `Core.lua` globals
- Tests: Not applicable (no test framework)

**New UI Component:**
- Implementation: `UI.lua`
- Add in `CreateBridgeUI()` or create new function following existing pattern
- Refresh logic: Add to `RefreshMessages()` or `RefreshRoster()` as appropriate

**New Slash Command:**
- Implementation: `Commands.lua`
- Add elseif clause in main command handler
- Update help text at end of file

**New Protocol Message Type:**
- Define prefix in `Core.lua` or at top of relevant file
- Add handler in `Messages.lua` (for chat) or create new file
- Add to event dispatch in `Events.lua` CHAT_MSG_ADDON handler

**Utilities/Helpers:**
- Shared helpers: `Utils.lua`
- File-specific helpers: Local functions at top of relevant file

## Special Directories

**.planning/:**
- Purpose: GSD planning and analysis documents
- Generated: By Claude via GSD commands
- Committed: Yes

**.git/:**
- Purpose: Git version control
- Generated: Yes
- Committed: No (excluded by nature)

**.claude/:**
- Purpose: Claude Code configuration
- Generated: By Claude Code
- Committed: Per user preference

## Load Order (from MNet.toc)

1. `Core.lua` - Must load first (defines GB global, constants, state)
2. `Utils.lua` - Helpers used by other files
3. `Handshake.lua` - Connection protocol (depends on Core)
4. `Messages.lua` - Message handling (depends on Core, Utils)
5. `RosterSync.lua` - Roster sync (depends on Core, Messages)
6. `UI.lua` - Interface (depends on Core, Utils, Messages)
7. `Events.lua` - Event handlers (depends on all above)
8. `Commands.lua` - Slash commands (depends on UI, Core)

**Critical:** Files receive shared `GB` table via Lua varargs `local addonName, GB = ...`

## File Size Reference

| File | Lines | Purpose |
|------|-------|---------|
| UI.lua | ~2100 | Largest - full UI implementation |
| Messages.lua | ~1200 | Message handling, relay logic |
| RosterSync.lua | ~800 | Roster sync protocol |
| Core.lua | ~700 | State, queues, relay election |
| Events.lua | ~490 | Event handlers |
| Handshake.lua | ~490 | Connection protocol |
| Commands.lua | ~280 | Slash commands |
| Utils.lua | ~250 | Helper functions |

---

*Structure analysis: 2026-01-17*
