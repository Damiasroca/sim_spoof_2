# User Guide

## Installation

### Transfer the script

**Via ADB (from PC):**

```bash
adb push sim_spoof.sh /data/local/tmp/
```

**Via Termux (on device):**

```bash
wget -O /data/local/tmp/sim_spoof.sh <your-raw-github-url>
```

### Run

```bash
su
sh /data/local/tmp/sim_spoof.sh
```

The script requires root. If you forget `su`, it will tell you:

```
[×] This script must be run as root.
    Run:  su -c 'sh /data/local/tmp/sim_spoof.sh'
```

---

## Interactive Setup

The script validates every input and loops until you provide a valid value. Nothing is written until you confirm.

### Legal Disclaimer

Type `y` to accept responsibility and proceed. Any other input aborts.

### MCCMNC

The Mobile Country Code + Mobile Network Code that identifies a carrier. Must be exactly 5 or 6 digits.

| MCCMNC | Carrier |
|--------|---------|
| `90188` | ReBullet Internet (Seychelles) |
| `25001` | MTS (Russia) |
| `310260` | T-Mobile (USA) |
| `23415` | Vodafone (UK) |

Look up codes at [mcc-mnc.com](https://www.mcc-mnc.com/).

### Operator Name

Display name for the spoofed carrier (e.g., `ReBullet Internet`). Cannot be empty. Shell-special characters are stripped automatically to prevent injection.

### ISO Country Code

Two-letter ISO 3166-1 alpha-2 code (e.g., `SC` for Seychelles, `RU` for Russia). Automatically lowercased.

### Timezone

Must follow `Region/City` format (e.g., `Europe/Moscow`, `America/New_York`, `Asia/Tokyo`).

### SIM Slot Selection

```
  [1] SIM 1 only
  [2] SIM 2 only
  [3] Both slots (default)
```

When spoofing a single slot, the other slot's real carrier identity is preserved by reading its current value at runtime.

### TTL Value

Time To Live for outgoing packets. Default `64`. Carriers use TTL differences to detect tethering — a uniform TTL defeats this.

| Value | Typical OS |
|-------|-----------|
| `64` | Linux / Android (most common) |
| `128` | Windows |

### DNS Provider

```
  [1] Cloudflare    1.1.1.1 / 1.0.0.1
  [2] Google        8.8.8.8 / 8.8.4.4
  [3] Quad9         9.9.9.9 / 149.112.112.112
  [4] Yandex        77.88.8.8 / 77.88.8.1
  [5] Custom
```

Each provider includes primary + secondary servers for failover, plus IPv6 addresses. Custom DNS prompts for all four addresses with format validation.

### Confirmation

A full summary is displayed:

```
=========================================
  Configuration Summary
=========================================
  MCCMNC:     90188 (MCC=901 MNC=88)
  Operator:   ReBullet Internet
  ISO:        sc
  Timezone:   Europe/Moscow
  SIM Slots:  Both
  TTL:        64
  DNS IPv4:   1.1.1.1 / 1.0.0.1
  DNS IPv6:   2606:4700:4700::1111 / 2606:4700:4700::1001
  IMEI 1:     014832756109283
  IMEI 2:     097215483062841
  Serial:     aK7mR2xP9nQ4
=========================================

Apply these settings? (y/n):
```

Type `y` to proceed. The script then:

1. Backs up and removes the SSAID file
2. Downloads the ad-blocking hosts file
3. Generates three boot scripts in `/data/adb/service.d/`
4. Sets executable permissions
5. Prompts for reboot

---

## Command-Line Flags

### `--dry-run`

Preview the full setup without writing any files:

```bash
sh sim_spoof.sh --dry-run
```

Goes through every prompt and shows the configuration summary, but no files are created, deleted, or modified.

### `--uninstall`

Remove all installed components and optionally restore the SSAID backup:

```bash
sh sim_spoof.sh --uninstall
```

The uninstaller:
1. Lists all SIM-Spoof scripts and the hosts module
2. Asks for confirmation before deleting
3. Offers to restore the SSAID backup if one exists
4. Prompts for a reboot

---

## Updating Configuration

Run the script again. It overwrites the previous boot scripts with your new configuration.

```bash
su
sh /data/local/tmp/sim_spoof.sh
```

A reboot is required after each change.

---

## Verifying

After rebooting, check the spoofed properties:

```bash
# Carrier identity
getprop gsm.operator.numeric
getprop gsm.operator.alpha
getprop gsm.sim.operator.iso-country

# Device identifiers
getprop ro.serialno
getprop persist.vendor.radio.imei1
getprop persist.vendor.radio.imei2

# Timezone
getprop persist.sys.timezone

# TTL
cat /proc/sys/net/ipv4/ip_default_ttl

# DNS
getprop net.dns1
getprop net.dns2
```

Check the log for warnings or errors:

```bash
cat /data/local/tmp/sim_spoof.log
```
