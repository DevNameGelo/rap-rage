# Steal an Egg — Rage Hub (alpha)

A single-file Luau script for the Roblox game **Steal an Egg**, built on the
[Rage Hub](https://github.com/devnamegelo/Rage-Hub) window library (v1.0.0).
One `.lua` file, no forks, no extra assets — loads straight from this repo.

> **Current build: alpha · passive load** (commit `6dcfeaa2`)
> Executing the script makes **zero client-to-server calls** — see
> [Passive load](#passive-load--the-anti-detection-design).

---

## Quick start

Any Luau executor works (built and tuned for Delta / mobile). Capabilities used:

| Capability | Used for | Required |
|---|---|---|
| `loadstring` + `game:HttpGet` | loading this script + the UI library | yes |
| `readfile` / `writefile` / `isfile` / `makefolder` | config save & load | yes |
| `queue_on_teleport` | Auto Execute across server hops | optional |
| `VirtualUser` / `VirtualInputManager` | Anti AFK virtual input | optional |

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"))()
```

The window library itself is pulled at runtime from the
[Rage-Hub repo](https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua)
and is not bundled here. There are **no sliders anywhere** — every number is an
internal constant tuned from RageDump evidence.

---

## Window layout (3 tabs)

### 🥚 Steal

| Control | What it does |
|---|---|
| **Status** | Live engine status line (job phase, carry state, cooldowns) |
| **Instant Steal** | Tap the game's own Steal button; the script flies the egg straight to the SafeZone |
| **Auto Steal** | Steal a matching egg, escape straight to the SafeZone, repeat |
| **Rarity** (dropdown, multi) | Egg rarity filter — not set = random. Built live from the game's own catalog (field-egg rarities only) |
| **Biome** (dropdown, multi) | Area filter — not set = random. Real areas only (WIP areas hidden) |
| **Auto Treadmill** | Wears YOUR plot's treadmill (no flying — the server relocates you itself) |
| **Help Friend (Manual Steal)** | Your manual steals get dropped at the Forest middle for a friend instead of redeemed |
| **Auto Help Friend** | AFK mode: auto-steal matching eggs and drop them at the Forest middle |

### 🏃 Player

| Control | What it does |
|---|---|
| **Anti Ragdoll** | Local anti-fling hygiene: motors, physics junk, launch clamp, player collisions. The 2.5 s server ragdoll can still happen |

### 🧰 Misc

| Section | Controls |
|---|---|
| **Session** | **Anti AFK** (default ON — virtual input every 45 s so the game's own idle detector stays quiet) · **Auto Reconnect** (rejoins after a kick or disconnect, up to 8 tries) · **Auto Execute** (queues this script for the next server — survives hops and the game's own AFK hop) |
| **Auto Sell** | **Sell Eggs** / **Sell Pets** + rarity filters. Every 5 s via the satchel's own `SellSelection` remote. Not set = sell all *unprotected* items — placed / favourite / fused eggs and equipped / favourite / fused pets are never sold |
| **Eggs** | **Auto Place Egg** (wear tool, then place on a free spot of your plot, 5+ studs from other eggs) · **Auto Hatch Egg** (`AskHatch` → 6.2 s → `AskFinishHatch`, the game's own timing) |
| **Pets & Events** | **Auto Catch Butterfly** (unverified remote shapes — swings the net when a butterfly blooms in reach; chases only while idle; auto-disables on refusal) · **Auto Place Best Pet** (wears best pets whenever new pets appear, every 30 s) |
| **Economy** | **Auto Claim Money** (away-earnings claim + codex redeem, every 2 minutes) · **Auto Upgrade Treadmill** (buys the next tier when affordable) · **Auto Buy Trail** (buys the most expensive affordable shop trail, then equips it) |
| **Config** | **Auto Save Config** (saves toggles/filters 1.2 s after any change) · **Auto Load Config** (restores the saved config on execute — this preference itself lives outside the config) |
| **Server** | **Hop to Lowest Server** (6 samples, keeps servers seen in every sample, lowest player count) · **Unload** (restores camera, replication focus and collisions, then closes the window) |
| **Low Profile** | Live summary of the passive-load guarantees below |

---

## How it moves

Steals use a **CFrame-stepped glide** — the movement style that already worked
before the anti-cheat got aggressive — not tweens or raw CFrame spam:

- 500 studs/s cruise, +50 studs vertical offset, climb and cruise together
- vertical descent only inside the last 25 studs, stops 3 studs above target
- velocity zeroed every frame so nothing fights the humanoid
- ground raycast gating with hover + re-stream (`RequestStreamAroundAsync` +
  `ReplicationFocus`, the game's own cutscene pattern) before long flights
- takeoff **ramps up from standstill** and the final studs **brake to a stop**,
  so every replicated position delta stays smooth — no teleport-like spikes
- armed anti-TP regions are read from the map and **flown over, around, or the
  egg is refused** — never bypassed

---

## Passive load — the anti-detection design

Older builds were detected within ~5 seconds of execution *with no features
on*, because the load path itself was noisy. This build's load path is
minimal, matching the builds that loaded clean:

1. **Zero C→S calls at load.** Executing the script builds the window,
   connects read-only server→client listeners, and nothing else. No remotes,
   no game-controller requires, no polling loops. (The only default-ON
   feature, Anti AFK, is client-local virtual input.)
2. **Snapshot on request only.** The egg list builds passively from the
   game's own `FieldEggShifted` / `FieldEggBatchShifted` / `FieldEggGone`
   events. The one-shot snapshot remote is called **at most once per
   session**, only after a steal feature is switched on, never earlier than
   10 s after load, never on respawn, single pcall, no retry.
3. **No game controllers.** Nothing under `ReplicatedStorage/Controllers` is
   ever required. Pure `Data.*` catalog modules (rarity, assets, treadmills,
   trails, butterflies) load lazily inside pcalls, only when a feature needs
   them.
4. **Isolated config.** Saves live in `RageHub/StealAnEgg_alpha/`, so a
   config saved by an older build can never auto-apply. First run starts
   from defaults.
5. **Lazy start + 15 s grace.** Every automation supervisor is created when
   its toggle first goes ON — not at load — and every automation tick waits
   out a 15-second startup grace.
6. **Smooth replication.** See the glide ramp/brake notes above.
7. **No hooks, no tampering.** Nothing hooks, blocks, fakes or races the
   anti-cheat or RigSync. No `hookmetamethod`, no `firesignal` on server
   events, no remote forgery or replay.

**Honest limit:** a server that checks raw movement speed could still flag
500 studs/s glides. No honest script can hide that, and this one refuses to
fake its way around it.

---

## Config & files

| File | Purpose |
|---|---|
| `RageHub/StealAnEgg_alpha/` | Config folder inside your executor's workspace directory — created on first save |
| `RageHub/StealAnEgg_alpha/_prefs.json` | Auto Save / Auto Load preferences (read *before* the window exists, so they survive config wipes) |

Auto Load restores a saved config 0.35 s after execute. Config changes save
1.2 s after the last change. **Unload** restores camera, replication focus
and player collisions, disconnects every listener, and closes the window.

---

## Version history

| Commit | Version | What changed |
|---|---|---|
| `dd37846` | **v2** (Flight Edition) | Velocity flight, direct remotes (no prompt/GUI clicking), delivery strategies, live filters |
| `1103fc0` | **v1** | Full rebuild: CFrame glide engine, direct-escape steal workflow (no nest waiting), recovery loop, live rarity/biome filters, anti-TP region avoidance, death-resilient runtime |
| `5d27aa6` | **alpha** | Automation (gear) tab merged into Misc — 3 tabs total; Auto Load infinite-loop + notification spam fixed; glide takeoff ramp + braking added |
| `6dcfeaa2` | **alpha · passive load** (current) | The anti-detection rebuild: zero C→S calls at load, snapshot-once-on-request, no controller requires, isolated config folder, lazy supervisors + 15 s grace |

---

## Verified vs hypothesis (honest status)

Development was **static** — nothing in this file was executed inside Roblox.
It passes `luau-compile` and `luau-analyze` (two toolchain versions) with zero
non-environment warnings. Remote calls use the exact shapes the game's own
client sends, taken from RageDump logs:

- **[VERIFIED]** — `AskFieldEggCarry`, `AskFieldEggDrop`, `SellSelection`,
  `AskWearStill` / `AskDoff`, `AskHatch` / `AskFinishHatch`, `AskPlaceEgg`,
  `WearBest`, `AskCollect` / `AskRedeemAll`, teleport/join flow
- **[HYPOTHESIS]** — butterfly swing remote, trail `AskChoose`: shapes
  inferred, always called inside pcall with auto-disable on refusal

## Verify the passive load yourself (RageDump)

1. Make sure no toggles are saved (fresh config folder, or Auto Load off).
2. RageDump **START** → execute the script → **MARK** when the "loaded"
   notification appears.
3. Wait **60 seconds** → **DONE**.
4. In `Remotes_*.txt`, the **`C->S(exec)`** section must be **empty** — the
   script made no client-to-server calls after load.
5. Switch features on one at a time and re-run: each feature should only add
   its documented calls (Auto Steal → snapshot once ≥10 s in +
   `AskFieldEggCarry`/`AskFieldEggDrop`; Auto Sell → `SellSelection`;
   Auto Treadmill → `AskWearStill`/`AskDoff`; …).

---

## Disclaimer

For educational and personal use on your own account. Automation can still be
detected and result in a ban — the passive-load design minimizes the load-time
footprint but cannot make cheating undetectable. Game updates can break remote
shapes at any time. Use at your own risk.
