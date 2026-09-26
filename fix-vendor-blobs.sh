#!/usr/bin/env bash
# fix-vendor-blobs.sh — post-generation fixups for vendor/motorola/*.
#
# RUN THIS AFTER EVERY extract-files.py OR setup-makefiles.py RUN.
# Those regenerate vendor/motorola/ from scratch, and vendor/motorola is not a
# git repo, so any edit made there by hand is silently destroyed by the next
# extract with no diff to warn you. Everything that would otherwise be a manual
# edit lives here instead, idempotent, so a re-extract costs one command.
#
# History: the allocator fixup below was originally applied by hand. A later
# re-extract wiped it and the build failed with a dependency error 40 lines from
# anything that had been touched, which is exactly the failure mode this script
# exists to prevent.
#
#   ./fix-vendor-blobs.sh          # apply
#   ./fix-vendor-blobs.sh --check  # verify only, non-zero if a fixup is missing
set -u
TOP=$(cd "$(dirname "$0")/../../.." && pwd)
BP="$TOP/vendor/motorola/sm8635-common/Android.bp"
# Reject unknown arguments rather than silently falling through to APPLY mode.
# Fixup 4 mutates a BINARY blob in a directory that is not a git repo, at an
# unchanged file size -- an accidental apply would leave no diff and no way to
# tell a deliberately patched tree from an accidentally patched one.
CHECK=0
case "${1:-}" in
    "")      ;;
    --check) CHECK=1 ;;
    *) echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac
rc=0

[ -f "$BP" ] || { echo "missing $BP -- run setup-makefiles.py first" >&2; exit 1; }

# --- fixup 1: RETIRED 2026-08-11 -- superseded by ;DISABLE_DEPS in
#     proprietary-files.txt, which is git-tracked and survives a re-extract.
#     Kept as a GUARD ONLY: it now just asserts the generated file is free of the
#     bad state, and fails loudly if the annotation is ever dropped. Do not go
#     back to rewriting the generated Android.bp; see the note in
#     proprietary-files.txt for why that fix was wrong twice over.
#
# Original problem, for context:
#
# vendor.qti.hardware.display.allocator-service is BOTH a blob we ship and a
# source module (hardware/qcom-caf/sm8650/display/gralloc/Android.bp:166). Soong
# merges the prebuilt and the source module under the one name, so their
# dependencies are merged too -- and they disagree:
#
#   blob DT_NEEDED     -> android.hardware.graphics.allocator-V2-ndk.so
#   source module      -> android.hardware.graphics.allocator-V1-ndk  (line 192)
#
# giving "depends on multiple versions of the same aidl_interface:
# android.hardware.graphics.allocator-V1-ndk-source, ...-V2-ndk-source" and no
# ninja file at all. extract_utils writes V2 because that is genuinely what the
# binary links against; the build only tolerates one, and the source module is
# what the rest of the display stack is built against, so V2 is rewritten to V1
# HERE, on the prebuilt only.
#
# Scoped deliberately to the one module: there are ~58 other V2 references in
# the generated file and they are all fine, because only this module collides
# with a same-named source module.
fix_allocator() {
    local start end
    start=$(grep -n 'name: "vendor.qti.hardware.display.allocator-service"' "$BP" | head -1 | cut -d: -f1)
    [ -n "$start" ] || { echo "  allocator: module not found (blob no longer shipped?) -- skipping"; return 0; }
    end=$((start + 80))
    if sed -n "${start},${end}p" "$BP" | grep -q 'allocator-V[12]-ndk'; then
        echo "  allocator: shared_libs still lists an AIDL allocator -- the ;DISABLE_DEPS"
        echo "             annotation on vendor/bin/hw/vendor.qti.hardware.display.allocator-service"
        echo "             in proprietary-files.txt has been lost. Restore it; do NOT hand-edit"
        echo "             the generated Android.bp."
        return 1
    fi
    echo "  allocator: deps correctly dropped via ;DISABLE_DEPS (ok)"
    return 0
}

# --- fixup 2: WLAN host-driver config that extract_utils cannot extract
#
# /vendor/firmware/wlan/qca_cld/kiwi_v2/WCNSS_{prc,qcom}_cfg.ini are ABSOLUTE
# SYMLINKS in the stock dump (-> /vendor/etc/wifi/kiwi_v2/...), which are broken
# on the host because there is no /vendor here. extract_utils reports them as
# "file not found" and skips them, and the build then dies in ninja with
#   missing and no known rule to make it
# because proprietary-files.txt lists them as real files. It lists them as real
# files ON PURPOSE -- see the note there: the firmware loader reads them during
# early boot, and without them the qca_cld3_kiwi_v2 probe fails and there is no
# wlan0 at all. Do not "fix" this by deleting the entries.
#
# The symlink TARGET (vendor/etc/wifi/kiwi_v2/*.ini) extracts fine, so resolve
# the links here by copying the target content into place.
fix_wlan_ini() {
    local dst="$TOP/vendor/motorola/sm8635-common/proprietary/vendor/firmware/wlan/qca_cld/kiwi_v2"
    local src="$TOP/vendor/motorola/sm8635-common/proprietary/vendor/etc/wifi/kiwi_v2"
    local f n=0 missing=0
    for f in WCNSS_prc_cfg.ini WCNSS_qcom_cfg.ini; do
        if [ ! -s "$src/$f" ]; then
            echo "  wlan: SOURCE MISSING $src/$f -- re-run extract-files.py"; missing=1; continue
        fi
        if [ -s "$dst/$f" ] && cmp -s "$src/$f" "$dst/$f"; then continue; fi
        if [ "$CHECK" = "1" ]; then echo "  wlan: $f missing or stale -- FIXUP MISSING"; missing=1; continue; fi
        mkdir -p "$dst" && cp "$src/$f" "$dst/$f" && n=$((n+1))
    done
    [ "$missing" = "1" ] && return 1
    if [ "$n" -gt 0 ]; then echo "  wlan: resolved $n symlink(s) into real files"; else echo "  wlan: already resolved (ok)"; fi
    return 0
}

# --- fixup 3: moto-telephony.xml points at the wrong partition ---------------
# proprietary-files.txt relocates both halves from system/ to system_ext/:
#   system/etc/permissions/moto-telephony.xml : system_ext/etc/permissions/...
#   system/framework/moto-telephony.jar       : system_ext/framework/...
# but the XML's own file= attribute still names the ORIGINAL path, so the
# declaration dangles and the library is silently dropped at boot:
#
#   I SystemConfig: Ignore shared library moto-telephony:
#     /system/framework/moto-telephony.jar does not exist
#
# org.codeaurora.ims declares `uses-library moto-telephony`, so with the library
# ignored PackageManager reports
#   E PackageManager: updateAllSharedLibrariesLPw failed: Package
#     org.codeaurora.ims requires unavailable shared library ...
# and the app runs unlinked. Rewrite the attribute to match where we install it.
fix_moto_telephony_xml() {
    local dir="$TOP/vendor/motorola/sm8635-common/proprietary/system_ext/etc/permissions"
    local missing=0 n=0 name f
    for name in moto-telephony moto-ims-ext; do
        f="$dir/$name.xml"
        if [ ! -f "$f" ]; then
            echo "  $name.xml: not extracted (ok, blob not shipped)"
            continue
        fi
        if ! /usr/bin/grep -q "\"/system/framework/$name.jar\"" "$f"; then
            echo "  $name.xml: already points at system_ext (ok)"
            continue
        fi
        if [ "$CHECK" = "1" ]; then
            echo "  $name.xml: still points at /system/framework -- FIXUP MISSING"
            missing=1
            continue
        fi
        /usr/bin/sed -i "s|\"/system/framework/$name\.jar\"|\"/system_ext/framework/$name.jar\"|" "$f"
        echo "  $name.xml: repointed to /system_ext/framework"
        n=$((n+1))
    done
    [ "$missing" = "1" ] && return 1
    return 0
}

# --- fixup 4: every inbound SMS is swallowed by QCRIL power-on optimisation ---
# QCRIL buffers each MT SMS until the Android telephony UI declares itself
# ready, and releases the buffer only when power-on optimisation is OFF or the
# cached "ATeL UI status" is non-zero. On this ROM the status is never set, so
# the buffer is never flushed and the message is dropped:
#
#   QCRIL_SMS  qcril_qmi_sms_unsolicited_indication_cb_helper:
#              msg_id (0x0001) QMI_WMS_EVENT_REPORT_IND        <- SMS arrives
#   qcril_qmi_nas_get_atel_ui_status_from_cache:
#              .. known ATEL UI STATUS Valid 1, value 0        <- UI "not ready"
#   QCRIL_SMS  qcril_qmi_sms_update_mt_sms_with_ack_needed_power_opt_buffer:
#              MT SMS ACK NEEDED Power Opt buffer length 1     <- buffered, then lost
#
# THIS IS A WORKAROUND, NOT A CURE -- read this before "improving" it.
# The sender exists and we already ship it. com.qti.phone (the QtiTelephony apk)
# has PowerUpOptimization.trySendPhoneReadyForSlot() -> QtiMsgTunnelClient
# .sendAtelReadyStatus(), which sends QCRIL_EVT_HOOK_SET_ATEL_UI_STATUS
# (524314 = 0x8001A) via QcRilHook; vendor side, OemHookStable::setUiStatus is
# the ONLY writer of ui_status=1. It fires only when ALL FOUR of
# mIsOemHookConnected, mIsRilConnectedForSlot[slot], mIsImsStackUpForSlot[slot]
# and !mIsAtelReadySentForSlot[slot] hold. On this port one of them never
# becomes true, so ATEL ready is never sent and the gate never opens. (The apk
# only began installing at all with e9af8e9 -- before that there was genuinely
# no sender, which is how this was first mis-diagnosed as "nothing sends it".)
#
# DIAGNOSTIC for whoever picks this up: `logcat | grep "Not sending ATEL ready:"`
# names the failing precondition directly. Making that precondition true is the
# real cure and would let power-opt stay enabled. Until then, this stands.
#
# Stock sets poweron_opt in no prop file, so stock runs power-opt enabled and
# relies entirely on that app sending the hook.
#
# The switch is persist.vendor.radio.poweron_opt, and it is NOT an Android
# property here: stock's own /vendor/bin/qtisetprop writes qcril_properties_table
# and falls back to setprop only when the property is ABSENT from that table. It
# is present (def_val=1), so `setprop persist.vendor.radio.poweron_opt 0` does
# nothing -- which is why an earlier attempt at this was wrongly recorded as
# refuted. The DB is the lever.
#
# SEEDING, so this survives `fastboot -w`: vendor/etc/init/hw/init.qcom.rc:394
# copies this prebuilt to /data/vendor/radio/qcrilNr_prebuilt.db on EVERY boot
# ("copy prebuilt qcril.db files always"), and qcril_db_copy_from_prebuilt
# streams it into qcrilNr.db whenever /data carries no version row -- i.e. after
# a wipe. That transfer is a raw file copy, NOT a re-population from def_val, so
# the `value` column is carried over intact.
#
# NOTHING CLOBBERS THE VALUE AFTERWARDS, but not for the obvious reason. The
# qcrildb_version row carries TWO independent counters: `def_val` (=15) gates
# upgrade/config/ and upgrade/other/, while `value` (=29) gates upgrade/ecc/
# (Motorola repurposed the column). A script replays only when
# local < file_ver <= vendor, and on fresh /data the runtime DB is a byte copy
# of the prebuilt, so both counters already match and nothing replays at all.
# The one destructive script -- 0006.0_config.sql, whose
# `INSERT OR REPLACE INTO qcril_properties_table(property, def_val)` would blank
# the value column -- needs local < 6, and local is 15 and only ever rises, so it
# is permanently unreachable. ecc/ 30..58 do run on a fresh DB but never touch
# this property and never write qcril_properties_table destructively.
# NOTE: "the highest shipped script is 0015.0" is true only of config/; ecc/
# ships up to 58. Do not re-derive this argument from the file list alone.
#
# Verified on-device. Same SMS, same RIL restart, only this value changed:
#   before  -> ATEL UI STATUS consulted, "MT SMS ACK NEEDED Power Opt buffer"
#   after   -> transfer_route_mt_message_valid 1, GsmInboundSmsHandler
#              EVENT_NEW_SMS, QMI_WMS_SEND_ACK_RESP qmi error 0, message in inbox
fix_qcril_poweron_opt() {
    local db="$TOP/vendor/motorola/sm8635-common/proprietary/vendor/etc/qcril_database/qcrilNr.db"
    local prop="persist.vendor.radio.poweron_opt"
    local cur n

    # This blob is listed unconditionally in proprietary-files.txt, so absence is
    # never "ok" -- it means the extract failed and the build cannot succeed.
    if [ ! -s "$db" ]; then
        echo "  qcrilNr.db: missing or empty -- re-run extract-files.py"
        return 1
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "  qcrilNr.db: sqlite3 not on PATH -- cannot apply the inbound-SMS fixup"
        return 1
    fi
    # Keep "unreadable" separate from "row absent": a failed sqlite3 prints
    # nothing to stdout, so testing the output alone would blame the wrong thing
    # and send the reader off to re-derive a fixup that is fine.
    if ! n=$(sqlite3 "$db" "select count(*) from qcril_properties_table where property='$prop';" 2>/dev/null); then
        echo "  qcrilNr.db: not readable as sqlite -- re-run extract-files.py"
        return 1
    fi
    if [ "$n" != "1" ]; then
        echo "  qcrilNr.db: '$prop' row is GONE -- the upstream blob changed shape."
        echo "              Re-derive the inbound-SMS fixup before shipping this."
        return 1
    fi
    cur=$(sqlite3 "$db" "select ifnull(value,'<null>') from qcril_properties_table where property='$prop';")
    if [ "$cur" = "0" ]; then
        echo "  qcrilNr.db: power-on optimisation already disabled (ok)"
        return 0
    fi
    if [ "$CHECK" = "1" ]; then
        echo "  qcrilNr.db: $prop value=$cur, expected 0 -- FIXUP MISSING"
        return 1
    fi
    sqlite3 "$db" "update qcril_properties_table set value='0' where property='$prop';" || return 1
    echo "  qcrilNr.db: power-on optimisation disabled (was $cur) -- inbound SMS"
    return 0
}

# --- fixup 5: prune the declared-but-absent HALs from manifest_cliffs.xml -----
#
# manifest_cliffs.xml IS this device's VINTF manifest. arcfox sets
# ro.boot.product.vendor.sku=cliffs, and libvintf reads manifest_$(sku).xml and
# RETURNS (VintfObject.cpp) -- device/motorola/sm8635-common/manifest.xml is
# never consulted, so entries cannot be removed there. The file is a blob we
# ship verbatim, which is why the edit lives in this script: the next
# extract-files.py restores stock's copy byte for byte.
#
# Nine <hal> blocks, ten declared instances, are removed. Every one is
# unregistered on the shipping build -- absent from `lshal list -i` and
# `service list`.
#
# ⚠️ CORRECTED 2026-09-01 (independent review). This comment used to add "and
# with no server anywhere in the built vendor image". That is FALSE. The image
# holds a server artifact for every one of the nine -- four named for the pruned
# fqname exactly (com.motorola.hardware.display.touch@1.2-service,
# motorola.hardware.camera.desktop@2.0-service,
# motorola.hardware.health.storage@1.0-service,
# vendor.zui.hardware.ifaa@1.0-service) plus four -impl.so passthroughs. The
# search behind that claim excluded any file whose name began with the interface
# package, which excluded the servers themselves.
#
# The REAL reason nothing serves them is that commit 7d26208 deleted their init
# .rc files (etc/init went 143 -> 121). That is a configuration fact, not a
# property of the blobs. ⚠️ Consequence: if any of those .rc files is ever
# restored, the matching manifest entry must be restored WITH it, or the service
# will start and then fail to register ("must be in VINTF manifest in order to
# register").
#
#   com.dsi.ant                            @1.0::IAnt/default
#   com.motorola.hardware.display.touch    @1.2::IMotTouch/default
#   motorola.hardware.camera.desktop       @1.0 and @2.0 ::ICameraDesktop/default
#   motorola.hardware.health.storage       @1.0::IMotStorage/default
#   vendor.nxp.nxpnfc_aidl                 INxpNfc/default
#   vendor.qti.hardware.bluetooth_audio    @2.1::IBluetoothAudioProvidersFactory/default
#   vendor.qti.hardware.btconfigstore      @2.0::IBTConfigStore/default
#   vendor.qti.hardware.fm                 @1.0::IFmHci/default
#   vendor.zui.hardware.ifaa               @1.0::IIFAADevice/default
#
# WHY THIS IS NOT COSMETIC. optional="true" in the framework matrix keeps
# `check_vintf` quiet, but a declaration is a PROMISE to clients: hwservicemanager
# and servicemanager treat a declared name as one that may yet appear, so
# getService() waits on it instead of failing fast. That is the same
# declared-but-absent trap that hung mediaserver over the Dolby c2 stores and left
# IMediaCasService declared and unserved. It is also a submission problem --
# VtsTrebleVintfTargetTest walks the device manifest and requires every declared
# HAL to be retrievable.
#
# ⚠️ NOT REMOVED, deliberately: vendor.qti.hardware.wifi.wifilearner
# @1.0::IWifiStats/wifiStats. Keep it out of the drop list -- but note the reason
# first written here ("unlike these nine it HAS a real server") does NOT
# distinguish it: all nine have servers too, and wifilearner is equally
# unstartable, since its .rc ships only in stock and not in our image. It is kept
# because /vendor/bin/wifilearner is a standalone daemon we could plausibly start,
# so the declaration marks an open question rather than a phantom.
#
# Removing a declaration cannot break a working feature here: nothing is serving
# any of these, so there is no client that succeeds today and would stop.
#
# ⚠️ Do not generalise that sentence. It holds for HIDL -- libhidl's
# ServiceManagement.cpp:924-940 retry loop needs a manifest entry, so undeclared
# means an immediate nullptr -- but NOT for AIDL:
# frameworks/native/cmds/servicemanager/ServiceManager.cpp:473-475 calls
# tryStartService() without consulting isVintfDeclared.
MANIFEST_CLIFFS_DROP="
com.dsi.ant
com.motorola.hardware.display.touch
motorola.hardware.camera.desktop
motorola.hardware.health.storage
vendor.nxp.nxpnfc_aidl
vendor.qti.hardware.bluetooth_audio
vendor.qti.hardware.btconfigstore
vendor.qti.hardware.fm
vendor.zui.hardware.ifaa
"

fix_manifest_cliffs() {
    local m="$TOP/vendor/motorola/sm8635-common/proprietary/vendor/etc/vintf/manifest_cliffs.xml"

    # Listed unconditionally in proprietary-files.txt, so absence means the
    # extract failed -- not something to skip past quietly.
    if [ ! -s "$m" ]; then
        echo "  manifest_cliffs.xml: missing or empty -- re-run extract-files.py"
        return 1
    fi

    CHECK="$CHECK" DROP="$MANIFEST_CLIFFS_DROP" python3 - "$m" <<'PY'
import os, re, sys

path = sys.argv[1]
drop = set(os.environ["DROP"].split())
check = os.environ["CHECK"] == "1"
src = open(path, encoding="utf-8").read()

# Match whole <hal ...> ... </hal> blocks and key them on <name>. The file is
# machine-generated with one element per line, but the regex does not rely on
# that -- only on <hal> blocks not nesting, which VINTF manifests never do.
blocks = list(re.finditer(r"[ \t]*<hal\b.*?</hal>\n", src, re.S))
present = {}
for b in blocks:
    n = re.search(r"<name>([^<]+)</name>", b.group(0))
    if n and n.group(1) in drop:
        present[n.group(1)] = b

unknown = drop - {re.search(r"<name>([^<]+)</name>", b.group(0)).group(1)
                  for b in blocks
                  if re.search(r"<name>([^<]+)</name>", b.group(0))}
if unknown and not present:
    # Already pruned: every name is gone. That is the idempotent success case.
    print("  manifest_cliffs.xml: %d phantom HAL declarations already removed (ok)"
          % len(drop))
    sys.exit(0)

if check:
    print("  manifest_cliffs.xml: %d phantom HAL declarations still present -- "
          "FIXUP MISSING" % len(present))
    for n in sorted(present):
        print("      %s" % n)
    sys.exit(1)

out = src
for n, b in present.items():
    out = out.replace(b.group(0), "", 1)
open(path, "w", encoding="utf-8").write(out)
print("  manifest_cliffs.xml: removed %d phantom HAL declarations" % len(present))
for n in sorted(present):
    print("      %s" % n)
PY
}

# --- fixup 6: do not declare ISecureElement/eSE1 (manifest_cliffs/pineapple) ---
#
# The eSE1 instance of android.hardware.secure_element-service.qti is the
# AP-side (TZ over SPI) view of the Thales secure element that ALSO carries the
# eUICC. On this build its open never succeeds -- `GPQESE_CMD_OPEN failed :
# 0xFFFF000E` on every init(), stock kernel chain or ours, NFC on or off,
# permissive or enforcing -- and the HAL's recovery for that failure is
# `STSEReset: ST54J SE reset (cold_reset)`, which power-cycles the shared chip:
# the eUICC stops answering the modem <=20 ms later for ~258 s, every cold boot
# (logs/esim-investigation-20260923/, ESIM-FINDINGS.md §5c).
#
# Nothing on this build consumes eSE1: the Thales StrongBox keymint and weaver
# (its only OMAPI clients on stock) are deliberately not shipped (see
# proprietary-files.txt, "STRONGBOX (Thales) DROPPED"). Removing the declaration
# makes servicemanager refuse the HAL's eSE1 registration and com.android.se skip
# the terminal -- init() is never called, so the SE is never reset. SIM1/SIM2
# (android.hardware.secure_element.xml fragment) are untouched. Measured
# 2026-09-26: with the HAL prevented from initialising eSE1 the slot-2 wedge is
# gone and the eUICC enumerates 260 ms after LOADED (coldboot-sehal-disabled-run1,
# coldboot-no-ese1-decl-run1).
#
# Revert this fixup (and restore the block) the day StrongBox/weaver return AND
# the eSE1 open works; until then a declared eSE1 is a promise that ends in a
# reset of the eSIM.
fix_manifest_ese1() {
    local rc=0 m
    for m in manifest_cliffs.xml manifest_pineapple.xml; do
        local f="$TOP/vendor/motorola/sm8635-common/proprietary/vendor/etc/vintf/$m"
        if [ ! -s "$f" ]; then echo "  $m: missing or empty -- re-run extract-files.py"; rc=1; continue; fi
        CHECK="$CHECK" python3 - "$f" <<'PY2' || rc=1
import os, re, sys
path = sys.argv[1]; name = os.path.basename(path); check = os.environ["CHECK"] == "1"
src = open(path, encoding="utf-8").read()
pat = re.compile(r"[ \t]*<hal\b[^>]*>\s*<name>android\.hardware\.secure_element</name>\s*"
                 r"<fqname>ISecureElement/eSE1</fqname>\s*</hal>\n", re.S)
hits = pat.findall(src)
if not hits:
    if "eSE1" in src:
        print("  %s: eSE1 still mentioned in an unexpected shape -- FIXUP MISSING" % name); sys.exit(1)
    print("  %s: ISecureElement/eSE1 already undeclared (ok)" % name); sys.exit(0)
if check:
    print("  %s: ISecureElement/eSE1 still declared -- FIXUP MISSING" % name); sys.exit(1)
out = pat.sub("", src)
open(path, "w", encoding="utf-8").write(out)
print("  %s: removed the ISecureElement/eSE1 declaration (%d block)" % (name, len(hits)))
PY2
    done
    return $rc
}

echo "fix-vendor-blobs:"
fix_allocator || rc=1
fix_wlan_ini  || rc=1
fix_moto_telephony_xml || rc=1
fix_qcril_poweron_opt || rc=1
fix_manifest_cliffs || rc=1
fix_manifest_ese1 || rc=1
exit $rc
