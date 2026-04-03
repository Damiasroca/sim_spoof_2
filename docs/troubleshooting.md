# Troubleshooting

## Installer Errors

### "This script must be run as root"

The script is not running with root privileges. Run it from a root shell:

```bash
su
sh /data/local/tmp/sim_spoof.sh
```

Or in one command:

```bash
su -c 'sh /data/local/tmp/sim_spoof.sh'
```

### "Root solution not installed"

The directory `/data/adb/service.d/` does not exist. This means either:

- No root solution is installed
- Your root solution doesn't support `service.d` boot scripts

Ensure you have [Magisk](https://github.com/topjohnwu/Magisk), [KernelSU](https://kernelsu.org/), or [APatch](https://github.com/bmax121/APatch) properly installed. If using Magisk, verify with `magisk --version` in a root shell.

### "iptables not found" / "ip6tables not found"

Your ROM is missing iptables binaries in `/system/bin/`. This is uncommon but can happen on heavily stripped custom ROMs.

**Fix:** Install a busybox module that includes iptables through your root manager.

### "Download failed"

The hosts file or module download failed. Common causes:

- **No internet:** Verify connectivity with `ping 1.1.1.1`
- **DNS not resolving:** Try `ping raw.githubusercontent.com`
- **SSL issues:** The download helper tries `curl` first, then `wget --no-check-certificate`, then plain `wget`. If all fail, your device may lack both `curl` and a working `wget` with SSL support.

**Manual workaround:** Download the hosts file on your PC and push it:

```bash
# On PC
curl -o hosts https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
adb push hosts /data/adb/modules/sim-spoof-hosts/system/etc/hosts
```

---

## Runtime Issues

### Properties revert briefly

Android may periodically reset carrier properties when the modem re-registers with the network. `SIM-Service.sh` monitors `gsm.operator.numeric` every 60 seconds and re-applies the spoof if the value changed.

If you need faster re-application, edit the sleep interval:

```bash
su
sed -i 's/sleep 60/sleep 10/' /data/adb/service.d/SIM-Service.sh
```

Then reboot.

### Carrier name flickers on status bar

Same cause as above. The real carrier name appears briefly between the system resetting the property and the monitor re-applying it. The 60-second check interval means a worst-case 60-second window.

### BBR warning at boot

```
[!] BBR not available. Skipping.
```

Your kernel doesn't support BBR or BBR2 congestion control. This is non-critical — the script skips BBR setup and everything else works normally. BBR is an optimization, not a requirement.

### Tethering still detected by carrier

If the carrier still detects tethering despite TTL fixing:

1. **Check TTL is applied:** `cat /proc/sys/net/ipv4/ip_default_ttl` should show your configured value
2. **Check iptables rules:** `iptables -t mangle -L POSTROUTING -n` should show the TTL rule
3. **Try TTL 128** if your carrier expects Windows-like traffic
4. **DNS leaks:** Some carriers inspect DNS traffic. Ensure DNS redirection is active: `iptables -t nat -L OUTPUT -n`
5. **DPI (Deep Packet Inspection):** Some carriers use DPI that TTL fixing can't defeat. A VPN is the only reliable solution against DPI.

### Apps lost their licenses or 2FA

This happens because the SSAID (Settings Secure Android ID) was reset. Each app had a unique identifier that is now gone.

**To restore:** If you haven't rebooted multiple times, the backup may still be valid:

```bash
su
sh /data/local/tmp/restore_ssaid.sh
```

Or use the built-in uninstaller:

```bash
su
sh /data/local/tmp/sim_spoof.sh --uninstall
```

**Note:** Once you reboot after SSAID deletion, Android generates new SSAIDs. Restoring the backup at that point may cause conflicts. The backup is most useful immediately after running the spoof script, before the first reboot.

### DNS not redirecting

DNS redirection via iptables only catches traffic on port 53 (standard DNS). It does **not** capture:

- **DNS-over-TLS (DoT)** on port 853
- **DNS-over-HTTPS (DoH)** on port 443

If you have Private DNS enabled in Android settings (`Settings > Network > Private DNS`), DNS goes through DoT/DoH and bypasses the iptables rules. Disable Private DNS if you want iptables-based DNS redirection to work for all traffic.

---

## Log File

All operations are logged with timestamps to `/data/local/tmp/sim_spoof.log`. Check it for diagnostic information:

```bash
cat /data/local/tmp/sim_spoof.log
```

Example output:

```
[2026-04-02 21:15:03] [STEP] Checking environment...
[2026-04-02 21:15:03] [OK] bbr2 congestion control supported.
[2026-04-02 21:15:03] [OK] Environment OK.
[2026-04-02 21:15:45] [OK] SSAID backed up to /data/local/tmp/settings_ssaid.xml.bak
[2026-04-02 21:15:45] [OK] SSAID removed.
[2026-04-02 21:15:46] [STEP] Downloading hosts file...
[2026-04-02 21:15:48] [OK] Hosts file updated (72841 bytes).
[2026-04-02 21:15:48] [ADD] Creating SIM-Spoof.sh...
[2026-04-02 21:15:48] [ADD] Creating SIM-Service.sh...
[2026-04-02 21:15:48] [ADD] Creating SIM-TTL.sh...
```

---

## Full Reset

To completely undo all changes and return to the pre-spoof state:

```bash
su
sh /data/local/tmp/sim_spoof.sh --uninstall
```

This removes:
- All three boot scripts from `/data/adb/service.d/`
- The hosts overlay module from `/data/adb/modules/`
- Optionally restores the SSAID backup

After rebooting, Android reads real SIM values from the modem and all spoofed properties are gone. The iptables rules are not persistent (they only exist because the boot scripts create them), so they also disappear.
