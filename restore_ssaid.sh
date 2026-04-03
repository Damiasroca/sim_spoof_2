#!/system/bin/sh
# ================================================================
#  SSAID Restore Utility
#  Restores the settings_ssaid.xml backup created by sim_spoof.sh
# ================================================================

SSAID="/data/system/users/0/settings_ssaid.xml"
SSAID_BAK="/data/local/tmp/settings_ssaid.xml.bak"

if [ "$(id -u)" -ne 0 ]; then
    echo "[×] This script must be run as root."
    echo "    Run:  su -c 'sh $0'"
    exit 1
fi

echo "========================================="
echo "    SSAID Restore Utility"
echo "========================================="
echo ""

if [ ! -f "$SSAID_BAK" ]; then
    echo "[×] No backup found at $SSAID_BAK"
    echo "    Nothing to restore."
    exit 1
fi

_bak_date=$(ls -la "$SSAID_BAK" 2>/dev/null | awk '{print $6, $7, $8}')
_bak_size=$(wc -c < "$SSAID_BAK" 2>/dev/null | tr -d ' ')
echo "  Backup:   $SSAID_BAK"
echo "  Size:     ${_bak_size} bytes"
echo "  Date:     ${_bak_date:-unknown}"
echo ""

if [ -f "$SSAID" ]; then
    _cur_size=$(wc -c < "$SSAID" 2>/dev/null | tr -d ' ')
    echo "  Current SSAID exists (${_cur_size} bytes)."
    echo "  Restoring will overwrite it."
else
    echo "  No current SSAID file (already deleted)."
fi

echo ""
printf "Restore backup? (y/n): "
read _confirm
case "$_confirm" in
    y|Y)
        cp "$SSAID_BAK" "$SSAID" 2>/dev/null
        if [ $? -eq 0 ]; then
            chown system:system "$SSAID" 2>/dev/null
            chmod 600 "$SSAID" 2>/dev/null
            echo ""
            echo "[✓] SSAID restored successfully."
            echo ""
            echo "  Reboot is required for changes to take effect."
            echo "    [1] Reboot now"
            echo "    [2] Reboot later"
            printf "  Choose (1-2): "
            read _rb
            case "$_rb" in
                1) reboot ;;
                2) echo "  Reboot manually when ready." ;;
                *) echo "  Reboot manually when ready." ;;
            esac
        else
            echo ""
            echo "[×] Restore failed. Check permissions."
            exit 1
        fi
        ;;
    *)
        echo "  Aborted."
        ;;
esac
