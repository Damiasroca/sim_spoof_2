#!/system/bin/sh
# ================================================================
#  SIM Spoof Utility v2.0
#
#  Usage:
#    sh sim_spoof.sh              Install / configure
#    sh sim_spoof.sh --dry-run    Preview without applying
#    sh sim_spoof.sh --uninstall  Remove installed scripts
# ================================================================

# --------------- Busybox PATH setup ---------------
for _bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    [ -x "$_bb" ] && export PATH="$(dirname "$_bb"):$PATH" && break
done

# --------------- Constants ---------------
LOG="/data/local/tmp/sim_spoof.log"
SDIR="/data/adb/service.d"
SSAID="/data/system/users/0/settings_ssaid.xml"
SSAID_BAK="/data/local/tmp/settings_ssaid.xml.bak"
HOSTS_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
SERIAL_LEN=12
HOSTS_MOD_DIR="/data/adb/modules/sim-spoof-hosts"
HOSTS_DST="$HOSTS_MOD_DIR/system/etc/hosts"

# --------------- Parse flags ---------------
DRY_RUN=false
UNINSTALL=false
for _a in "$@"; do
    case "$_a" in
        --dry-run)   DRY_RUN=true ;;
        --uninstall) UNINSTALL=true ;;
    esac
done

# ======================== Root check =========================

if [ "$(id -u)" -ne 0 ]; then
    echo "[×] This script must be run as root."
    echo "    Run:  su -c 'sh $0'"
    exit 1
fi

# ======================== Functions =========================

log() {
    _lvl="$1"; shift
    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "-")
    { echo "[$_ts] [$_lvl] $*" >> "$LOG"; } 2>/dev/null
    case "$_lvl" in
        OK)   echo "[✓] $*" ;;
        WARN) echo "[!] $*" ;;
        ERR)  echo "[×] $*" ;;
        STEP) echo "[•] $*" ;;
        ADD)  echo "[+] $*" ;;
    esac
}

die() { log ERR "$*"; exit 1; }

sanitize() {
    printf '%s' "$1" | sed 's/[`$"\\!;|&(){}]//g'
}

# --------------- Validators ---------------

ok_mccmnc() {
    case "$1" in
        [0-9][0-9][0-9][0-9][0-9])      return 0 ;;
        [0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;;
    esac
    return 1
}

ok_iso() {
    case "$1" in [a-zA-Z][a-zA-Z]) return 0 ;; esac
    return 1
}

ok_tz() {
    case "$1" in */*) return 0 ;; esac
    return 1
}

ok_ipv4() { echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }
ok_ipv6() { echo "$1" | grep -qE '^[0-9a-fA-F:]+$'; }

ok_ttl() {
    case "$1" in
        [1-9] | [1-9][0-9] | [12][0-9][0-9]) return 0 ;;
    esac
    return 1
}

# --------------- Random / crypto ---------------

rnd() {
    _r=$(od -A n -t u4 -N 4 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ -z "$_r" ] && _r=$RANDOM
    echo $((_r % $1))
}

rand_serial() {
    _out="" _i=0 _clen=${#CHARS}
    while [ "$_i" -lt "$1" ]; do
        _idx=$(rnd "$_clen")
        _out="${_out}${CHARS:$_idx:1}"
        _i=$((_i + 1))
    done
    echo "$_out"
}

luhn_check_digit() {
    _digits="$1" _sum=0 _len=${#_digits} _i=0
    while [ "$_i" -lt "$_len" ]; do
        _pos=$((_len - 1 - _i))
        _d="${_digits:$_pos:1}"
        if [ $((_i % 2)) -eq 0 ]; then
            _d=$((_d * 2))
            [ "$_d" -gt 9 ] && _d=$((_d - 9))
        fi
        _sum=$((_sum + _d))
        _i=$((_i + 1))
    done
    echo $(( (10 - (_sum % 10)) % 10 ))
}

generate_imei() {
    _rbi=$(printf '%02d' "$(rnd 100)")
    _tac=$(printf '%06d' "$(rnd 1000000)")
    _ser=$(printf '%06d' "$(rnd 1000000)")
    _body="${_rbi}${_tac}${_ser}"
    echo "${_body}$(luhn_check_digit "$_body")"
}

# --------------- Download helper ---------------

dl() {
    _url="$1"; _out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$_out" "$_url" 2>/dev/null && return 0
    fi
    wget -q --no-check-certificate -O "$_out" "$_url" 2>/dev/null && return 0
    wget -qO "$_out" "$_url" 2>/dev/null && return 0
    return 1
}

# --------------- Hosts module ---------------

setup_hosts_module() {
    mkdir -p "$HOSTS_MOD_DIR/system/etc" 2>/dev/null || die "Failed to create module directory."

    cat > "$HOSTS_MOD_DIR/module.prop" <<'MODPROP'
id=sim-spoof-hosts
name=SIM Spoof Hosts
version=v1.0
versionCode=1
author=sim-spoof
description=Ad-blocking hosts file for SIM Spoof utility. Uses StevenBlack/hosts.
MODPROP

    if [ ! -f "$HOSTS_DST" ]; then
        cp /system/etc/hosts "$HOSTS_DST" 2>/dev/null || echo "127.0.0.1 localhost" > "$HOSTS_DST"
    fi

    log OK "Hosts module created at $HOSTS_MOD_DIR"
}

# --------------- Uninstall ---------------

do_uninstall() {
    clear
    echo "========================================="
    echo "    SIM Spoof — Uninstall"
    echo "========================================="
    echo ""

    _found=false
    for _f in SIM-Spoof.sh SIM-Service.sh SIM-TTL.sh; do
        [ -f "$SDIR/$_f" ] && _found=true && echo "  Found: $SDIR/$_f"
    done
    [ -d "$HOSTS_MOD_DIR" ] && _found=true && echo "  Found: $HOSTS_MOD_DIR"

    if ! $_found; then
        echo "  No SIM-Spoof components found. Nothing to remove."
        exit 0
    fi

    echo ""
    printf "Remove all SIM-Spoof components? (y/n): "
    read _c
    case "$_c" in
        y|Y)
            for _f in SIM-Spoof.sh SIM-Service.sh SIM-TTL.sh; do
                rm -f "$SDIR/$_f" 2>/dev/null && echo "  Removed: $_f"
            done
            if [ -d "$HOSTS_MOD_DIR" ]; then
                rm -rf "$HOSTS_MOD_DIR" 2>/dev/null && echo "  Removed: hosts module"
            fi
            if [ -f "$SSAID_BAK" ]; then
                echo ""
                printf "Restore SSAID backup from %s? (y/n): " "$SSAID_BAK"
                read _r
                case "$_r" in
                    y|Y) cp "$SSAID_BAK" "$SSAID" && echo "  SSAID restored." || echo "  Restore failed." ;;
                esac
            fi
            echo ""
            log OK "Uninstall complete. Reboot to take effect."
            ;;
        *) echo "  Aborted." ;;
    esac
    exit 0
}

# ======================== Main ==========================

$UNINSTALL && do_uninstall

clear
echo "========================================="
echo "     SIM Spoof Utility v2.0"
echo "========================================="
echo ""
echo "  LEGAL DISCLAIMER"
echo "  Modifying device identifiers such as"
echo "  IMEI is illegal in many jurisdictions."
echo "  This tool is provided for educational"
echo "  purposes only. You accept full legal"
echo "  responsibility for its use."
echo ""
echo "========================================="
echo ""
printf "Accept and continue? (y/n): "
read _accept
case "$_accept" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
esac

if $DRY_RUN; then
    echo ""
    log WARN "DRY-RUN mode enabled. No changes will be written."
fi

echo ""
log STEP "Checking environment..."
[ ! -d "$SDIR" ] && die "Root solution not installed ($SDIR not found)."

if [ ! -d "$HOSTS_MOD_DIR" ]; then
    log STEP "Setting up hosts module..."
    setup_hosts_module
fi

BBR=""
if grep -qw 'bbr2' /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    BBR="bbr2"
elif grep -qw 'bbr' /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    BBR="bbr"
fi
[ -n "$BBR" ] && log OK "$BBR congestion control supported." || log WARN "BBR not available. Skipping."

which iptables  >/dev/null 2>&1 || die "iptables not found."
which ip6tables >/dev/null 2>&1 || die "ip6tables not found."
log OK "Environment OK."

# --------------- User input ---------------

echo ""
while true; do
    printf "MCCMNC (5-6 digits, e.g. 90188): "
    read MCCMNC
    ok_mccmnc "$MCCMNC" && break
    log WARN "Must be 5 or 6 digits."
done
MCC="${MCCMNC:0:3}"
MNC="${MCCMNC:3}"

while true; do
    printf "Operator name (e.g. ReBullet Internet): "
    read _raw_op
    [ -n "$_raw_op" ] && break
    log WARN "Cannot be empty."
done
OPERATOR=$(sanitize "$_raw_op")

while true; do
    printf "ISO country code (2 letters, e.g. SC): "
    read _raw_iso
    ok_iso "$_raw_iso" && break
    log WARN "Must be exactly 2 letters."
done
ISO=$(echo "$_raw_iso" | tr '[:upper:]' '[:lower:]')

while true; do
    printf "Timezone (e.g. Europe/Moscow): "
    read _raw_tz
    ok_tz "$_raw_tz" && break
    log WARN "Must contain a '/' (e.g. Region/City)."
done
TZ_VAL=$(sanitize "$_raw_tz")

echo ""
echo "SIM Slot Selection:"
echo "  [1] SIM 1 only"
echo "  [2] SIM 2 only"
echo "  [3] Both slots (default)"
printf "Choose (1-3): "
read SLOT
case "$SLOT" in 1|2) ;; *) SLOT=3 ;; esac

echo ""
printf "TTL value (default 64): "
read _raw_ttl
if [ -z "$_raw_ttl" ]; then
    TTL=64
elif ok_ttl "$_raw_ttl"; then
    TTL="$_raw_ttl"
else
    log WARN "Invalid TTL. Using default 64."
    TTL=64
fi

echo ""
while true; do
    echo "DNS Provider:"
    echo "  [1] Cloudflare   [2] Google   [3] Quad9"
    echo "  [4] Yandex       [5] Custom"
    printf "Choose (1-5): "
    read _dc
    case "$_dc" in
        1)  D1="1.1.1.1";   D2="1.0.0.1"
            D6_1="2606:4700:4700::1111"; D6_2="2606:4700:4700::1001"; break ;;
        2)  D1="8.8.8.8";   D2="8.8.4.4"
            D6_1="2001:4860:4860::8888"; D6_2="2001:4860:4860::8844"; break ;;
        3)  D1="9.9.9.9";   D2="149.112.112.112"
            D6_1="2620:fe::fe";          D6_2="2620:fe::9";           break ;;
        4)  D1="77.88.8.8"; D2="77.88.8.1"
            D6_1="2a02:6b8::feed:0ff";   D6_2="2a02:6b8:0:1::feed:0ff"; break ;;
        5)
            while true; do printf "  Primary DNS IPv4: ";   read D1;   ok_ipv4 "$D1"   && break; log WARN "Invalid IPv4."; done
            while true; do printf "  Secondary DNS IPv4: "; read D2;   ok_ipv4 "$D2"   && break; log WARN "Invalid IPv4."; done
            while true; do printf "  Primary DNS IPv6: ";   read D6_1; ok_ipv6 "$D6_1" && break; log WARN "Invalid IPv6."; done
            while true; do printf "  Secondary DNS IPv6: "; read D6_2; ok_ipv6 "$D6_2" && break; log WARN "Invalid IPv6."; done
            break ;;
        *) log WARN "Invalid option." ;;
    esac
done

# --------------- Generate identifiers ---------------

SERIAL_NO=$(rand_serial "$SERIAL_LEN")
IMEI1=$(generate_imei)
IMEI2=$(generate_imei)

# --------------- Confirmation ---------------

_slot_label="Both"
[ "$SLOT" = "1" ] && _slot_label="SIM 1 only"
[ "$SLOT" = "2" ] && _slot_label="SIM 2 only"

echo ""
echo "========================================="
echo "  Configuration Summary"
echo "========================================="
echo "  MCCMNC:     $MCCMNC (MCC=$MCC MNC=$MNC)"
echo "  Operator:   $OPERATOR"
echo "  ISO:        $ISO"
echo "  Timezone:   $TZ_VAL"
echo "  SIM Slots:  $_slot_label"
echo "  TTL:        $TTL"
echo "  DNS IPv4:   $D1 / $D2"
echo "  DNS IPv6:   $D6_1 / $D6_2"
echo "  IMEI 1:     $IMEI1"
echo "  IMEI 2:     $IMEI2"
echo "  Serial:     $SERIAL_NO"
echo "========================================="
echo ""
printf "Apply these settings? (y/n): "
read _apply
case "$_apply" in
    y|Y) ;;
    *) echo "Aborted."; exit 0 ;;
esac

if $DRY_RUN; then
    echo ""
    log OK "Dry-run complete. No changes were made."
    exit 0
fi

# --------------- SSAID backup & removal ---------------

if [ -f "$SSAID" ]; then
    cp "$SSAID" "$SSAID_BAK" 2>/dev/null \
        && log OK "SSAID backed up to $SSAID_BAK" \
        || log WARN "SSAID backup failed."
    rm -f "$SSAID" 2>/dev/null \
        && log OK "SSAID removed." \
        || log WARN "SSAID removal failed."
else
    log WARN "SSAID file not found. Skipping."
fi

# --------------- Download hosts ---------------

log STEP "Downloading hosts file..."
if dl "$HOSTS_URL" "${HOSTS_DST}.tmp"; then
    _sz=$(wc -c < "${HOSTS_DST}.tmp" 2>/dev/null | tr -d ' ')
    if [ "${_sz:-0}" -gt 1000 ]; then
        mv "${HOSTS_DST}.tmp" "$HOSTS_DST"
        log OK "Hosts file updated (${_sz} bytes)."
    else
        rm -f "${HOSTS_DST}.tmp"
        log WARN "Downloaded hosts file suspiciously small (${_sz} bytes). Keeping existing."
    fi
else
    rm -f "${HOSTS_DST}.tmp"
    log WARN "Hosts download failed. Skipping."
fi

# --------------- Create SIM-Spoof.sh ---------------
log ADD "Creating SIM-Spoof.sh..."

# Prepare BBR line for SIM-TTL.sh (expanded here, embedded literally in the generated script)
if [ -n "$BBR" ]; then
    BBR_LINE="echo $BBR > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null"
else
    BBR_LINE="# BBR not available"
fi

cat > "$SDIR/SIM-Spoof.sh" <<SPOOF_EOF
#!/system/bin/sh
while [ "\$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

_SLOT=$SLOT

_dual() {
    case "\$_SLOT" in
        1) _o=\$(getprop "\$1" | cut -d, -f2); resetprop -n "\$1" "\$2,\${_o:-\$2}" ;;
        2) _o=\$(getprop "\$1" | cut -d, -f1); resetprop -n "\$1" "\${_o:-\$2},\$2" ;;
        3) resetprop -n "\$1" "\$2,\$2" ;;
    esac
}

_dual gsm.operator.iso-country "$ISO"
_dual gsm.sim.operator.iso-country "$ISO"
_dual gsm.operator.numeric "$MCCMNC"
_dual gsm.sim.operator.numeric "$MCCMNC"
_dual ro.cdma.home.operator.numeric "$MCCMNC"
_dual gsm.operator.alpha "$OPERATOR"
_dual ro.cdma.home.operator.alpha "$OPERATOR"
_dual gsm.sim.operator.alpha "$OPERATOR"
_dual ro.carrier.name "$OPERATOR"

case "\$_SLOT" in 1|3)
    resetprop -n ril.mcc.mnc0 "$MCCMNC"
    resetprop -n persist.vendor.mtk.provision.mccmnc.0 "$MCCMNC"
    resetprop -n vendor.gsm.ril.uicc.mccmnc "$MCCMNC"
    resetprop -n persist.vendor.radio.imei  "$IMEI1"
    resetprop -n persist.vendor.radio.imei1 "$IMEI1"
;; esac

case "\$_SLOT" in 2|3)
    resetprop -n ril.mcc.mnc1 "$MCCMNC"
    resetprop -n persist.vendor.mtk.provision.mccmnc.1 "$MCCMNC"
    resetprop -n vendor.gsm.ril.uicc.mccmnc.1 "$MCCMNC"
    resetprop -n persist.vendor.radio.imei2 "$IMEI2"
;; esac

resetprop -n debug.tracing.mcc "$MCC"
resetprop -n debug.tracing.mnc "$MNC"
resetprop -n persist.sys.timezone "$TZ_VAL"
resetprop -n gsm.operator.isroaming "false,false"
resetprop -n sys.wifitracing.started "0"
resetprop -n persist.vendor.wifienhancelog "0"
resetprop -n ro.com.android.dataroaming "0"
resetprop -n ro.serialno "$SERIAL_NO"
resetprop -n ro.boot.serialno "$SERIAL_NO"

settings put global auto_time_zone 1
settings put global development_settings_enabled 1
settings put global non_persistent_mac_randomization_force_enabled 1
settings put global restricted_networking_mode 0
settings put global bug_report 0
settings put global device_name Android
settings put secure tethering_allow_vpn_upstreams 1
settings put secure bluetooth_name Android

sed -i \\
    -e 's#<string name="adid_key">.*</string>#<string name="adid_key">00000000-0000-0000-0000-000000000000</string>#' \\
    -e 's#<int name="adid_reset_count" value=".*"/>#<int name="adid_reset_count" value="1"/>#' \\
    /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
SPOOF_EOF

# --------------- Create SIM-Service.sh ---------------
log ADD "Creating SIM-Service.sh..."

# Pick which comma-delimited field to monitor based on slot selection
[ "$SLOT" = "2" ] && _CHK_FIELD=2 || _CHK_FIELD=1

cat > "$SDIR/SIM-Service.sh" <<SERVICE_EOF
#!/system/bin/sh
while [ "\$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

sh $SDIR/SIM-Spoof.sh

while true; do
    sleep 60
    _cur=\$(getprop gsm.operator.numeric | cut -d, -f$_CHK_FIELD)
    [ "\$_cur" != "$MCCMNC" ] && sh $SDIR/SIM-Spoof.sh
done
SERVICE_EOF

# --------------- Create SIM-TTL.sh ---------------
log ADD "Creating SIM-TTL.sh..."

cat > "$SDIR/SIM-TTL.sh" <<TTL_EOF
#!/system/bin/sh
while [ "\$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

$BBR_LINE

# Flush stale rules from previous runs in this boot session
while iptables  -t nat    -D OUTPUT      -p tcp --dport 53 -j DNAT 2>/dev/null; do :; done
while iptables  -t nat    -D OUTPUT      -p udp --dport 53 -j DNAT 2>/dev/null; do :; done
while iptables  -t mangle -D POSTROUTING -j TTL --ttl-set $TTL 2>/dev/null; do :; done
while ip6tables -t mangle -D POSTROUTING -j HL  --hl-set  $TTL 2>/dev/null; do :; done
while iptables  -t mangle -D OUTPUT      -j TTL --ttl-set $TTL 2>/dev/null; do :; done
while ip6tables -t mangle -D OUTPUT      -j HL  --hl-set  $TTL 2>/dev/null; do :; done

# TTL / Hop Limit (applied globally so tethered traffic matches direct traffic)
iptables  -t mangle -A POSTROUTING -j TTL --ttl-set $TTL
ip6tables -t mangle -A POSTROUTING -j HL  --hl-set  $TTL
iptables  -t mangle -A OUTPUT      -j TTL --ttl-set $TTL
ip6tables -t mangle -A OUTPUT      -j HL  --hl-set  $TTL

# IPv4 DNS redirect
iptables -t nat -C OUTPUT -p tcp --dport 53 -j DNAT --to-destination $D1:53 2>/dev/null || \\
    iptables -t nat -I OUTPUT -p tcp --dport 53 -j DNAT --to-destination $D1:53
iptables -t nat -C OUTPUT -p udp --dport 53 -j DNAT --to-destination $D1:53 2>/dev/null || \\
    iptables -t nat -I OUTPUT -p udp --dport 53 -j DNAT --to-destination $D1:53

# IPv6 DNS redirect (silently skipped if kernel lacks ip6tables NAT)
ip6tables -t nat -C OUTPUT -p tcp --dport 53 -j DNAT --to-destination [$D6_1]:53 2>/dev/null || \\
    ip6tables -t nat -I OUTPUT -p tcp --dport 53 -j DNAT --to-destination [$D6_1]:53 2>/dev/null
ip6tables -t nat -C OUTPUT -p udp --dport 53 -j DNAT --to-destination [$D6_1]:53 2>/dev/null || \\
    ip6tables -t nat -I OUTPUT -p udp --dport 53 -j DNAT --to-destination [$D6_1]:53 2>/dev/null

# DNS system properties (primary + secondary for failover)
resetprop -n net.dns1 $D1
resetprop -n net.dns2 $D2
for _iface in eth0 ppp0 rmnet0 rmnet1 rmnet2 rmnet3 pdpbr1 wlan0 wlan1 wlan2 wlan3; do
    resetprop -n "net.\${_iface}.dns1" $D1
    resetprop -n "net.\${_iface}.dns2" $D2
done
TTL_EOF

# --------------- Set permissions ---------------

chmod +x "$SDIR/SIM-Spoof.sh" "$SDIR/SIM-Service.sh" "$SDIR/SIM-TTL.sh" 2>/dev/null \
    || log WARN "chmod failed on one or more scripts."

for _f in SIM-Spoof.sh SIM-Service.sh SIM-TTL.sh; do
    [ -f "$SDIR/$_f" ] || die "Failed to create $SDIR/$_f"
done

# --------------- Done ---------------

echo ""
echo "========================================="
echo "  [✓] Scripts installed successfully!"
echo "========================================="
echo "  Location: $SDIR/SIM-*.sh"
echo "  Log:      $LOG"
echo "  Backup:   $SSAID_BAK"
echo ""
echo "  Flags:"
echo "    --dry-run    Preview without changes"
echo "    --uninstall  Remove scripts & restore SSAID"
echo ""
echo "  GitHub: https://github.com/UhExooHw/sim-spoof"

while true; do
    echo ""
    echo "  Reboot is required to apply changes."
    echo "    [1] Reboot now"
    echo "    [2] Reboot later"
    printf "  Choose (1-2): "
    read _rb
    case "$_rb" in
        1) reboot; break ;;
        2) echo "  Reboot manually when ready."; break ;;
        *) log WARN "Invalid choice." ;;
    esac
done
