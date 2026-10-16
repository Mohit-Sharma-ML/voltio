# Gap #2 — Charge Limit: Research Spike (Findings)

**Date:** 2026-10-16 · **Scope:** research only, no code written · **Verdict: GO for read/display, NO-GO for firmware write, MAYBE (defer) for adapter mode.**

## Question

Can Voltio read and/or set the battery charge limit via SMC/firmware, as AlDente-class
apps do?

## Environment verified

| Item | Value |
|---|---|
| Machine | MacBook Pro (Mac16,7), Apple M4 Pro |
| macOS | 26.7.1 (25G241) |
| **System firmware** | **20457.1.29** |
| `pmset -g battlimit` | `No battery level limits set` (native Charge Limit never enabled on this Mac) |

## TL;DR verdict

1. **Reading charge/hold state: already done, expand it.** Voltio already reads
   `AppleSmartBattery` (`NotChargingReason`, `FullyCharged`,
   `ExternalChargeCapable`) — reads are **not gated** and never were. A
   "charge-limit awareness" feature (display the native limit/hold state, deep-link
   to System Settings → Battery) is shippable now with zero private-API risk.
2. **Writing a firmware charge limit: blocked on this firmware.** Apple gated every
   charge-control surface behind the private entitlement
   `com.apple.private.iokit.soc-limit` starting with macOS 27 Developer Beta 4
   firmware `20457.0.125.0.2+`, and the **same firmware ships in macOS 15.8 / 26.7
   security updates** — this machine has it. There is no unentitled route, even as
   root.
3. **The only working bypass is "adapter mode"** (hysteresis loop toggling wall
   power), which requires a **root daemon** — architecturally incompatible with
   Voltio's current sandboxed, single-.app, no-helper design. Defer.

## The evidence

### 1. macOS has a native Charge Limit since 26.4 — it is the sanctioned path

System Settings → Battery → (i) next to Charging offers a slider (80–100%). It is
enforced by `powerd` — i.e. **Apple already ships the feature**; the gate below exists
precisely so third parties cannot bypass powerd's enforcement.

### 2. Every write surface is entitlement-gated on firmware 20457.x

Verified independently by two contributors on the `batt` project (issue #152, and
batt's README compatibility matrix), against firmware `20457.1.29` — the **exact
firmware on this machine**:

| Surface | State on 20457.x | Even as root? |
|---|---|---|
| Legacy SMC keys `CH0B`/`CH0C`/`CHTE` | still enumerated but **zero-size placeholders** (`DataSize == 0`) | n/a |
| Firmware-limit SMC keys `bfF0`/`bfD0`/`bfE0` | all reads **and writes** return `kIOReturnNotPrivileged` (`0xe00002c1`) — filtered inside the `AppleSMC` user client | **gated** |
| `AppleSmartBattery` registry writes (`SetChargingEnabled`, `SetPowerMode`, `SetChargeLimitEnabled`, `ExternalChargeCapable`) | `0xe00002c1` | **gated** (reads fine) |
| `powerd` SOC-limit XPC / `IOPSLimitBatteryLevel` | `kIOReturnNotPrivileged`/`NotPermitted` | **gated** |

### 3. The "public" API symbols are private API in practice

The SDK exports these symbols in `IOKit.tbd` (verified locally):

- `IOPSCopyBatteryLevelLimits` — returns `NULL` to unentitled callers
- `IOPSLimitBatteryLevel` / `IOPSLimitBatteryLevelCancel` / `IOPSLimitBatteryLevelRegister`
- `IOPSShippingChargeLimitEnable` / `IOPSShippingChargeLimitGetState`

…but **none are declared in any public header** (verified: zero hits across
`IOKit.framework/Headers`). Shipping calls to them means: no App Store review path,
undefined behavior on unentitled invocation, and hard breakage whenever Apple changes
the private surface. This fails Voltio's "no private API" ground rule.

### 4. Adapter mode is the only unentitled control lever — at real cost

`CHIE` (adapter/wall-power cut) is **not gated**. `batt`'s adapter mode (PR #154) runs
a userspace hysteresis loop: cut wall power at the upper limit, restore at the lower
limit. Caveats they state themselves:

- Requires a **root launchd daemon** doing continuous SMC writes
- Only holds **while awake** (charging is disabled before sleep — it is userspace
  charge *inhibition*, not a firmware ceiling)
- Involves deliberately running the machine on battery while plugged in (extra
  charge cycles on the cells the feature is meant to protect)

For Voltio this would mean: a privileged helper (admin-auth install), an XPC service,
the host app remaining sandboxed while the daemon does IOKit work, plus sleep/wake
hook edge cases. That is a new subsystem with real failure modes — against a feature
Apple now ships natively (for the 80–100% range).

## Local runtime observations (read-only, this machine)

- `AppleSmartBattery` reads work normally: `StateOfCharge`, `FullyCharged`,
  `NotChargingReason` (=128 at capture: on battery, discharging),
  `ExternalChargeCapable`, plus `BatteryData.DailyMinSoc/DailyMaxSoc` (the gauge's
  daily SOC envelope — interesting for future "battery usage insights").
- Voltio's existing `NotChargingReason` decoding (`.optimizedChargingHold`,
  `.systemHold` → "Paused by macOS") is exactly the read-side of this feature space
  and is unaffected by the gate.
- `pmset -g battlimit` works as a getter for the native limit state (prints
  `No battery level limits set` when unset).

## Recommendation

**Phase 1 — "Charge limit awareness" (recommended, low risk, soon):**
- Read the native Charge Limit state (`pmset -g battlimit` parse and/or
  `AppleSmartBattery` hold-reason decode — both read-only).
- Surface it in the panel + a Settings hint: "Native charge limit: 80% (set in
  System Settings → Battery)" / "Paused by macOS: Optimized Charging hold".
- Deep-link button to `x-apple.systempreferences:com.apple.settings.battery`.
- Zero private API, zero entitlements, aligns with (rather than fights) Apple's
  enforcement.

**Phase 2 — adapter-mode limiting (defer, revisit only on user demand):**
- Only worth it if users ask for sub-80% limits and accept a root daemon + its
  caveats. If pursued: study `batt`'s backend-selection logic (MIT) and write our
  own; keep the daemon completely separate from the sandboxed app; make it opt-in
  with loud warnings.

**Never:** call `IOPSLimitBatteryLevel`/`IOPSShippingChargeLimit*` or write SMC
charge keys from the app. Gated, headerless, rejection-prone — and Apple's gate is
deliberate policy, not an oversight to engineer around.

## Sources

- batt README compatibility matrix + "gated firmware" section
  (github.com/charlie0129/batt) — independently matches this machine's firmware
- batt issue #152 (gating verification incl. `AppleSmartBattery` write probes and
  `powerd` SOC-limit symbols) and PR #154 (adapter mode)
- Apple support doc HT102338 (Optimized Battery Charging / Charge Limit, 26.4+)
- Local verification: firmware version, `pmset -g battlimit`, `AppleSmartBattery`
  reads, SDK header/tbd symbol cross-check (2026-10-16)
