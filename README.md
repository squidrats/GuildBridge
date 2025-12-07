# GuildBridge – README

GuildBridge links **two guilds’ guild chats** (cross-faction, cross-realm) using a Battle.net relay.  
Only **one or more relay characters per guild** need the addon.  
Everyone else sees the bridged messages normally in guild chat — no addon required.

---

## 📌 Requirements

- Two relay characters (one in each guild)
- Those two players must be **BattleTag friends**
- Both must have the addon installed
- Both must enable mirroring

---

## 📌 Setup Instructions

### 1. Add your partner as a Battle.net friend

- Battle.net Friends List → Add Friend → Enter BattleTag
- Both must accept the friend request.

---

### 2. Set your partner’s BattleTag in the addon

On each relay:
```
/gbridge partner Battletag#1234
```
Example:
```
/gbridge partner Squidface#1884
```

You should see:
```
GuildBridge: found partner relay: <Name-Realm> id <number>
```

If you see:
```
partner BattleTag found, but no WoW character online.
```
→ Your partner must log into a WoW character.

---

### 3. Enable bridging

On each relay:
```
/gbridge enable
```

Check:
```
/gbridge status
```

Disable:
```
/gbridge disable
```

---

### 4. Optional: Use the GuildBridge UI window

Show UI:
```
/gbridge show
```

Hide:
```
/gbridge hide
```
Toggle:
```
/gbridge
```

Messages sent in the UI input box do **not** appear in your own guild chat — they go only to the partner guild.

---

## 📌 How It Works

### Guild chat → mirrored to partner guild

Messages in guild chat on one side appear in the other guild formatted like:
```
<MEGA> Player: message
<MDGA> Player: message
```

Long guild names are automatically shortened.

---

### UI chat → one-way to partner guild

Typing into the addon’s UI input box:

- Sends the message to the partner guild
- Does *not* appear in your own guild chat
- Does *not* loop or echo back

---

## 📌 Multi-Relay Support

Multiple characters in the same guild can:
```
/gbridge enable
```

The addon ensures:

- No duplicate bridged messages  
- No infinite loops  
- Only one echo per message per guild  

It uses:

- `lastEchoedGuildText` to avoid re-sending its own injected lines  
- `recentMessages` dedupe to ensure only one relay echoes each bridged message  

This means **several relays can be active with no spam**.

---

## 📌 Commands
```
gbridge – Toggle the UI window
/gbridge show – Show UI window
/gbridge hide – Hide UI window
/gbridge enable – Enable guild mirroring
/gbridge disable – Disable guild mirroring
/gbridge status – Show current mirroring state
/gbridge partner X – Set partner BattleTag (example: /gbridge partner Foo#1234)
/gbridge reload – Re-scan BNet friends for partner relay
```

---

## 📌 Troubleshooting

### Nothing shows in the other guild
Check on both relays:
```
/gbridge partner Battletag#1234
/gbridge enable
/gbridge status
/gbridge reload
```

Ensure both players are BattleTag friends and logged into WoW.

---

### “Partner BattleTag found, but no WoW character online”
Your partner must be logged into a WoW character, not just Battle.net.

---

### Duplicate messages
All relay characters must use the **multi-relay version** of the addon.

---

## 📌 Summary

- Works cross-faction and cross-realm  
- Only relay characters need the addon  
- Prevents loops and duplicate spam  
- UI is optional  
- Clean output: `<MEGA> Name: message`  


