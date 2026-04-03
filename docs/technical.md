# Technical Reference

## Architecture

The installer (`sim_spoof.sh`) runs interactively once, then generates three persistent boot scripts under `/data/adb/service.d/`. These scripts are executed automatically by the root solution (Magisk/KernelSU/APatch) on every boot, after `sys.boot_completed` is set to `1`.

```
sim_spoof.sh (interactive, runs once)
    ├── Creates:  /data/adb/service.d/SIM-Spoof.sh
    ├── Creates:  /data/adb/service.d/SIM-Service.sh
    ├── Creates:  /data/adb/service.d/SIM-TTL.sh
    ├── Creates:  /data/adb/modules/sim-spoof-hosts/  (Magisk module)
    ├── Backs up: /data/system/users/0/settings_ssaid.xml
    └── Downloads: hosts file from StevenBlack/hosts
```

On each boot:

```
Boot completed
    ├── SIM-Service.sh
    │       ├── Runs SIM-Spoof.sh once
    │       └── Monitors gsm.operator.numeric every 60s, re-runs if reset
    ├── SIM-TTL.sh
    │       ├── Sets BBR congestion control (if supported)
    │       ├── Flushes stale iptables rules
    │       ├── Applies TTL/HL mangle rules
    │       ├── Applies DNS DNAT rules (IPv4 + IPv6)
    │       └── Sets DNS system properties per interface
    └── sim-spoof-hosts module
            └── Overlays /system/etc/hosts via magic mount
```

---

## Generated Scripts

### SIM-Spoof.sh

Sets all spoofed system properties via `resetprop -n` and Android settings via `settings put`.

**Dual-value properties** (comma-separated `SIM1,SIM2` format) are handled by a `_dual()` helper function that respects the SIM slot selection:

- **Both slots:** sets `"spoofed,spoofed"`
- **Slot 1 only:** reads current slot 2 value via `getprop`, sets `"spoofed,original"`
- **Slot 2 only:** reads current slot 1 value via `getprop`, sets `"original,spoofed"`

**Per-slot properties** (like `ril.mcc.mnc0`, `persist.vendor.radio.imei1`) are set conditionally based on the slot selection.

### SIM-Service.sh

Runs `SIM-Spoof.sh` once at boot, then enters a monitoring loop:

```
sleep 60
check gsm.operator.numeric field (slot 1 or 2)
if value != expected MCCMNC → re-run SIM-Spoof.sh
```

This is event-driven rather than blind re-application. The 60-second interval balances responsiveness with resource efficiency (~1 `getprop` call per minute vs. the original's ~400 `resetprop` calls per minute).

### SIM-TTL.sh

Runs once at boot. Applies network-level rules:

1. BBR congestion control (if kernel supports it)
2. Flush any stale iptables/ip6tables rules from previous runs
3. TTL/HL mangle rules (POSTROUTING + OUTPUT)
4. DNS DNAT rules for IPv4 (port 53 TCP/UDP)
5. DNS DNAT rules for IPv6 (silently skipped if kernel lacks ip6tables NAT)
6. DNS system properties per network interface

---

## System Properties Modified

### Carrier Identity (dual-value, via `_dual()`)

| Property | Example Value |
|----------|---------------|
| `gsm.operator.iso-country` | `sc,sc` |
| `gsm.sim.operator.iso-country` | `sc,sc` |
| `gsm.operator.numeric` | `90188,90188` |
| `gsm.sim.operator.numeric` | `90188,90188` |
| `ro.cdma.home.operator.numeric` | `90188,90188` |
| `gsm.operator.alpha` | `ReBullet Internet,ReBullet Internet` |
| `ro.cdma.home.operator.alpha` | `ReBullet Internet,ReBullet Internet` |
| `gsm.sim.operator.alpha` | `ReBullet Internet,ReBullet Internet` |
| `ro.carrier.name` | `ReBullet Internet,ReBullet Internet` |

### Per-Slot Properties

| Property | Slot | Example |
|----------|------|---------|
| `ril.mcc.mnc0` | 1 | `90188` |
| `ril.mcc.mnc1` | 2 | `90188` |
| `persist.vendor.mtk.provision.mccmnc.0` | 1 | `90188` |
| `persist.vendor.mtk.provision.mccmnc.1` | 2 | `90188` |
| `vendor.gsm.ril.uicc.mccmnc` | 1 | `90188` |
| `vendor.gsm.ril.uicc.mccmnc.1` | 2 | `90188` |
| `persist.vendor.radio.imei` | 1 | `014832756109283` |
| `persist.vendor.radio.imei1` | 1 | `014832756109283` |
| `persist.vendor.radio.imei2` | 2 | `097215483062841` |

### Global Properties

| Property | Value | Purpose |
|----------|-------|---------|
| `debug.tracing.mcc` | `901` | MCC for tracing |
| `debug.tracing.mnc` | `88` | MNC for tracing |
| `persist.sys.timezone` | `Europe/Moscow` | Timezone |
| `gsm.operator.isroaming` | `false,false` | Disable roaming indicator |
| `sys.wifitracing.started` | `0` | Disable wifi tracing |
| `persist.vendor.wifienhancelog` | `0` | Disable wifi logging |
| `ro.com.android.dataroaming` | `0` | Disable data roaming |
| `ro.serialno` | `aK7mR2xP9nQ4` | Device serial |
| `ro.boot.serialno` | `aK7mR2xP9nQ4` | Boot serial |

### Android Settings

| Setting | Table | Value | Purpose |
|---------|-------|-------|---------|
| `auto_time_zone` | global | `1` | Auto timezone |
| `development_settings_enabled` | global | `1` | Developer options |
| `non_persistent_mac_randomization_force_enabled` | global | `1` | MAC randomization |
| `restricted_networking_mode` | global | `0` | Allow network for restricted profiles |
| `bug_report` | global | `0` | Disable bug reports |
| `device_name` | global | `Android` | Generic device name |
| `tethering_allow_vpn_upstreams` | secure | `1` | VPN over tethering |
| `bluetooth_name` | secure | `Android` | Generic BT name |

### Advertising ID

The Google advertising ID is reset to `00000000-0000-0000-0000-000000000000` by modifying `/data/data/com.google.android.gms/shared_prefs/adid_settings.xml`.

---

## iptables Rules

### TTL / Hop Limit (mangle table)

Applied globally so tethered traffic is indistinguishable from direct traffic.

```
iptables  -t mangle -A POSTROUTING -j TTL --ttl-set <TTL>
ip6tables -t mangle -A POSTROUTING -j HL  --hl-set  <TTL>
iptables  -t mangle -A OUTPUT      -j TTL --ttl-set <TTL>
ip6tables -t mangle -A OUTPUT      -j HL  --hl-set  <TTL>
```

### DNS Redirection (nat table)

All DNS traffic (port 53) is redirected to the configured DNS server.

```
iptables  -t nat -I OUTPUT -p tcp --dport 53 -j DNAT --to-destination <DNS_IPv4>:53
iptables  -t nat -I OUTPUT -p udp --dport 53 -j DNAT --to-destination <DNS_IPv4>:53
ip6tables -t nat -I OUTPUT -p tcp --dport 53 -j DNAT --to-destination [<DNS_IPv6>]:53
ip6tables -t nat -I OUTPUT -p udp --dport 53 -j DNAT --to-destination [<DNS_IPv6>]:53
```

IPv6 NAT rules are applied with `2>/dev/null` since many Android kernels lack `CONFIG_IP6_NF_NAT`.

### DNS System Properties

Primary and secondary DNS servers are set for every network interface:

```
net.dns1, net.dns2
net.<iface>.dns1, net.<iface>.dns2
```

Interfaces: `eth0`, `ppp0`, `rmnet0`-`rmnet3`, `pdpbr1`, `wlan0`-`wlan3`.

---

## IMEI Generation

IMEIs are 15-digit numbers: 2-digit RBI + 6-digit TAC + 6-digit serial + 1 check digit.

The first 14 digits are generated using `/dev/urandom` (via `od`), falling back to `$RANDOM` if unavailable. The 15th digit is computed using the **Luhn algorithm**:

1. Starting from the rightmost of the 14 digits, double every other digit
2. If a doubled digit exceeds 9, subtract 9
3. Sum all digits
4. Check digit = `(10 - sum % 10) % 10`

This produces structurally valid IMEIs that pass checksum validation.

---

## Serial Number Generation

A 12-character alphanumeric string generated from `/dev/urandom`. Each character is selected from `A-Z`, `a-z`, `0-9` (62 characters) using `od -A n -t u4 -N 4 /dev/urandom` for entropy.

---

## Hosts Module

The script creates a minimal Magisk-compatible module at `/data/adb/modules/sim-spoof-hosts/`:

```
sim-spoof-hosts/
├── module.prop
└── system/
    └── etc/
        └── hosts
```

This is recognized by Magisk, KernelSU, and APatch as a standard systemless module. The root solution overlays `system/etc/hosts` via bind mount — no OverlayFS required.

The hosts file is downloaded from [StevenBlack/hosts](https://github.com/StevenBlack/hosts) with integrity checking (file must be >1 KB). If the download fails, the system's original hosts file is used as a seed.

---

## File Locations

| Path | Created by | Purpose |
|------|-----------|---------|
| `/data/adb/service.d/SIM-Spoof.sh` | Installer | Property spoofing |
| `/data/adb/service.d/SIM-Service.sh` | Installer | Monitor + re-apply |
| `/data/adb/service.d/SIM-TTL.sh` | Installer | TTL + DNS + BBR |
| `/data/adb/modules/sim-spoof-hosts/` | Installer | Hosts overlay module |
| `/data/local/tmp/sim_spoof.log` | Installer + boot scripts | Timestamped log |
| `/data/local/tmp/settings_ssaid.xml.bak` | Installer | SSAID backup |

---

## Security Considerations

- All user inputs are validated (MCCMNC: 5-6 digits, ISO: 2 alpha, timezone: contains `/`, DNS: regex, TTL: 1-255)
- Operator name and timezone are sanitized via `sed` to strip shell metacharacters (`` ` $ " \ ! ; | & ( ) { } ``)
- Generated IMEIs use proper Luhn checksums
- Random values sourced from `/dev/urandom` instead of `$RANDOM`
- SSAID is backed up before deletion
- Hosts file download is verified by size before replacing existing
- The script checks for root at startup
- All file operations include error handling with logged warnings
