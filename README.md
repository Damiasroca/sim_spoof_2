# SIM Spoof v2.0

SIM identity, IMEI, and network fingerprint spoofing utility for rooted Android devices.

Generates persistent boot scripts that automatically apply spoofed carrier identity, device identifiers, TTL masking, and DNS redirection on every reboot.

## Quick Start

```bash
adb push sim_spoof.sh /data/local/tmp/
adb shell
su
sh /data/local/tmp/sim_spoof.sh
```

The interactive setup walks you through carrier identity (MCCMNC, operator, ISO, timezone), SIM slot selection, TTL, and DNS — then shows a full summary before applying.

## Features

- Carrier identity spoofing (MCC/MNC, operator name, ISO country)
- IMEI generation with valid Luhn checksums
- Serial number randomization via `/dev/urandom`
- Per-slot SIM spoofing (SIM 1, SIM 2, or both)
- TTL/Hop Limit fixing (configurable, IPv4 + IPv6)
- DNS redirection with primary + secondary failover (IPv4 + IPv6)
- Ad-blocking hosts file ([StevenBlack/hosts](https://github.com/StevenBlack/hosts))
- SSAID backup and restore
- Advertising ID reset
- BBR congestion control (when kernel supports it)
- `--dry-run` and `--uninstall` flags
- Input validation and shell injection protection
- Timestamped log file

## Requirements

- Rooted Android device: [Magisk](https://github.com/topjohnwu/Magisk), [KernelSU](https://kernelsu.org/), or [APatch](https://github.com/bmax121/APatch)
- Terminal: [Termux](https://termux.dev/) or `adb shell`
- Internet connection (for hosts file download)

No additional modules required — the script creates its own lightweight hosts module automatically.

## Warning: SSAID Reset

The script deletes the Android SSAID file (`settings_ssaid.xml`) to reset per-app identifiers. This **will cause some apps to lose their licenses, 2FA bindings, or login sessions** — they'll behave as if installed on a new device.

A backup is created at `/data/local/tmp/settings_ssaid.xml.bak` before deletion. To restore it (before rebooting, ideally):

```bash
su
sh /data/local/tmp/restore_ssaid.sh
```

Or use `sh sim_spoof.sh --uninstall` to remove all changes and restore the backup.

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/guide.md) | Full walkthrough of every prompt, flag, and feature |
| [Technical Reference](docs/technical.md) | Generated scripts, system properties, iptables rules, architecture |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and how to fix them |

## Files

| File | Purpose |
|------|---------|
| `sim_spoof.sh` | Main installer script |
| `restore_ssaid.sh` | Standalone SSAID backup restore |

## Acknowledgments

Based on [sim-spoof](https://github.com/UhExooHw/sim-spoof) by [UhExooHw](https://github.com/UhExooHw), licensed under the Apache License 2.0. This is a complete rewrite with significant additions.

Ad-blocking hosts provided by [StevenBlack/hosts](https://github.com/StevenBlack/hosts) (MIT License).

## License

[Apache License 2.0](LICENSE)

## Disclaimer

Modifying device identifiers such as IMEI is illegal in many jurisdictions. This tool is provided for educational purposes only. You accept full legal responsibility for its use.
