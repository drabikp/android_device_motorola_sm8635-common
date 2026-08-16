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
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
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

echo "fix-vendor-blobs:"
fix_allocator || rc=1
fix_wlan_ini  || rc=1
fix_moto_telephony_xml || rc=1
exit $rc
