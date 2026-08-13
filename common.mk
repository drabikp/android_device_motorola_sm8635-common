# Common makefile for Motorola SM8635 (pineapple).

COMMON_PATH := device/motorola/sm8635-common

PRODUCT_SOONG_NAMESPACES += $(COMMON_PATH)

# These directories declare their own Soong namespaces, so their modules are
# invisible -- PRODUCT_PACKAGES entries for them fail as "non-existent modules"
# -- until they are listed here.
#   hardware/qcom-caf/bootctrl                    android.hardware.boot-service.qti
#   vendor/qcom/opensource/commonsys-intf/display the vendor.qti.hardware.display.*
#                                                 AIDL interfaces
#   hardware/qcom-caf/wlan/qcwcn                  lib_driver_cmd_qcwcn, the QCA
#                                                 vendor-command backend that
#                                                 BOARD_WPA_SUPPLICANT_PRIVATE_LIB
#                                                 names, and libwifi-hal-qcom
PRODUCT_SOONG_NAMESPACES += hardware/qcom-caf/bootctrl
PRODUCT_SOONG_NAMESPACES += vendor/qcom/opensource/commonsys-intf/display
PRODUCT_SOONG_NAMESPACES += hardware/qcom-caf/wlan/qcwcn

# NOTE: the display composer/allocator/mapper are shipped as STOCK BLOBS, not
# built from source. Building them here was tried and reverted -- every SDM
# support library in the image is a bit-identical stock blob, and sdm::
# interfaces are private unversioned C++ vtables, so a source-built composer
# SIGSEGV'd inside the stock libsdmcore.so and restart-looped SF and zygote with
# it. See the DISPLAY STACK section in proprietary-files.txt.

# API level. Vendor is frozen at 34; see BoardConfigCommon.mk.
PRODUCT_SHIPPING_API_LEVEL := 34

# Treat the super-group partitions as dynamic. Without this nothing sizes them
# and build_image.py fails with KeyError: 'partition_size' for product.img,
# vendor.img, system_ext.img in turn. Must be set product-side: BoardConfig
# rejects it as readonly.
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# Partitions this OTA updates. AB_OTA_UPDATER alone is not enough: without this
# list the packager has no META/ab_partitions.txt and fails with
#   AssertionError: META/ab_partitions.txt is required for ab_update.
#
# vendor_dlkm and system_dlkm MUST be here. They are inside super, which we do
# flash, and delta_generator validates that every partition named in
# motorola_dynamic_partitions_partition_list (BoardConfigCommon.mk:258-264) has a
# payload entry. Omitting them broke `mka otapackage` outright:
#
#   ERROR:payload_generation_config.cc(262)] Cannot find partition vendor_dlkm
#     which is in motorola_dynamic_partitions_partition_list
#   FATAL: Check failed: payload_config.target.ValidateDynamicPartitionMetadata()
#
# ⚠️ The comment that used to sit here claimed this ROM "does not build"
# vendor_boot, vendor_dlkm, system_dlkm or dtbo. That is FALSE for all four --
# the build produces every one of them. What is true is narrower and is the
# actual reason for the exclusions below:
#
#   * vendor_dlkm/system_dlkm ARE built by us. The 287 + 60 modules are stock
#     (our prebuilt/ copies are byte-identical to the W1UXS36H dump), but the
#     build strips them -- ours ship out of
#     obj/PACKAGING/depmod_vendor_stripped_intermediates -- so the images we
#     pack into super are OURS, not stock's, and an OTA that skipped them would
#     leave the handset inconsistent with the super we flash.
#   * vendor_boot and dtbo are built too, but install-lineage-fastboot.sh
#     deliberately does NOT flash them (it flashes only boot, init_boot, super,
#     vbmeta, vbmeta_system). The stock copies are meant to stay on the handset,
#     so shipping ours via OTA would silently change behaviour. Keep them out.
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    product \
    system \
    system_ext \
    system_dlkm \
    vbmeta \
    vendor \
    vendor_dlkm

# Prebuilt kernel modules. 287 in vendor_dlkm, 60 in system_dlkm, extracted
# from the shipping firmware. These arrive via the blob manifest rather than
# being built, because this is a GKI device with no usable kernel source.
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(COMMON_PATH)/modules.load 2>/dev/null))

# =============================================================================
# HALs BUILT FROM SOURCE
# =============================================================================
# Everything below replaces a Motorola blob with the HAL the platform already
# compiles, following the shape of the official LineageOS device for this same
# SoC (xiaomi/peridot, SM8635, lineage-23.2), which declares ~220 packages and
# builds its HAL services rather than lifting them out of stock.
#
# The concrete defect this fixes, measured on the built image: TEN HAL service
# binaries shipped with NO init .rc at all, so init never started any of them --
#   android.hardware.health-service.qti      android.hardware.usb-service.qti
#   android.hardware.wifi-service            vendor.qti.hardware.memtrack-service
#   vendor.qti.hardware.vibrator.service     ... and five more
# extract_utils generates a cc_prebuilt_binary with no init_rc, so a blob HAL
# only starts if its .rc is ALSO listed in proprietary-files.txt by hand. The
# Soong modules below carry their own init_rc and vintf_fragments, so the .rc
# and the VINTF manifest entry come along automatically and cannot drift out of
# sync with the binary.
#
# Each entry here is paired with the removal of the corresponding line(s) from
# proprietary-files.txt -- adding one without the other gives
# "already defined by an in-tree source module".

# Boot control. Mandatory on A/B, and the first failure ever isolated on this
# device: the blob aborted in bootcontrol_init() because /dev/block/bootdevice
# did not exist, restart-looped, and init gave up at ~328s.
PRODUCT_PACKAGES += \
    android.hardware.boot-service.qti \
    android.hardware.boot-service.qti.recovery

# Health. Was shipped as a blob with no .rc, i.e. never started.
PRODUCT_PACKAGES += \
    android.hardware.health-service.qti \
    android.hardware.health-service.qti_recovery

# USB. Same -- blob present, no .rc.
PRODUCT_PACKAGES += \
    android.hardware.usb-service.qti \
    android.hardware.usb.gadget-service.qti

# Memtrack / vibrator / QSPA. All three had the same no-.rc defect.
PRODUCT_PACKAGES += \
    vendor.qti.hardware.memtrack-service

PRODUCT_PACKAGES += \
    vendor.qti.hardware.vibrator.service

PRODUCT_PACKAGES += \
    vendor.qti.qspa-service \
    qspa_vendor.rc

# Vendor service manager.
PRODUCT_PACKAGES += \
    vndservice \
    vndservicemanager

# KeyMint AIDL interface libraries, vendor variants.
#
# Motorola's keymint blobs (libqtikeymint.so, libtpa.so, libjc_keymint-thales.so
# and the two keymint service binaries) are COMPILED against keymint AIDL V3.
# Stock accommodates that by shipping keymint-V2-ndk.so and keymint-V3-ndk.so in
# /vendor/lib64 -- both were in stock's vendor image and missing from ours, which
# is why a previous session rewrote the blobs' DT_NEEDED to the V4 we did ship.
#
# That rewrite is now removed (see sm8635-common/extract-files.py). An AIDL NDK
# backend is not ABI-compatible across a version bump, and the symptom of forcing
# it was keymint-qti starting, going silent after three TimedRetryForwarder lines
# at 2.6s, and never registering IKeyMintDevice -- which stalls keystore2, then
# vold, then the boot. Shipping the versions the blobs actually want is the fix.
PRODUCT_PACKAGES += \
    android.hardware.security.keymint-V2-ndk.vendor \
    android.hardware.security.keymint-V3-ndk.vendor


# THE CURRENT BOOT BLOCKER. These two restore the dependencies of the
# libsensorndkbridge BLOB, and without them the device does not boot.
#
# AOSP builds a source module of that exact name
# (frameworks/hardware/interfaces/sensorservice/libsensorndkbridge, `proprietary:
# true`, so it installs to /vendor/lib64). Its shared_libs are what installed
# android.frameworks.sensorservice-V1-ndk.so into /vendor/lib64 -- verified in the
# 2026-08-07 target-files snapshot, which carries VENDOR/lib64/{the NDK lib 101968 B,
# libsensorndkbridge.so 85000 B = the AOSP build}.
#
# proprietary-files.txt then took the Motorola blob for the same name, because only
# the blob exports ASensorManager_getCurInstance, which qcrilNrd needs. extract_utils
# emits it with `prefer: true` (so it wins over the source module) and, because of
# ;DISABLE_DEPS, with NO shared_libs at all. The source module's dependency edges
# vanished with it, android.frameworks.sensorservice-V1-ndk.so stopped being
# installed to /vendor, and the blob became unloadable:
#
#   dlopen failed: library "android.frameworks.sensorservice-V1-ndk.so" not found:
#       needed by /vendor/lib64/libsensorndkbridge.so in namespace (default)
#
# Two things then die on it. libgnss.so DT_NEEDEDs libsensorndkbridge.so, so
# liblocation_api's runtime dlopen of libgnss fails ("LocSvc_LocationAPI:
# loadLibGnss: No gnss interface available"), LocationControlAPI::getInstance()
# returns NULL and the GNSS HAL null-derefs it in its own constructor -- 254
# SIGSEGVs. IGnss is declared in VINTF, so system_server's MAIN thread parks in an
# untimed waitForDeclaredService inside LocationManagerService's phase 600 and
# Watchdog kills it at 65s, forever. Same shape as the weaver bug. And qcrilNrd
# fails the identical link 104 times, which is the telephony outage that adding
# the blob was meant to fix in the first place.
#
# sensors-V2 is the blob's OTHER unmet DT_NEEDED (the AOSP module used V3, which is
# already shipped for the multihal). V2 is a frozen, vendor_available version, and
# several versions of one aidl_interface already coexist here as .vendor packages
# (display.config V2/V5/V7/V11 below), so this is the same pattern, not a new risk.
#
# Shipping the libs rather than dropping the blob keeps GNSS and telephony both
# fixed; dropping the blob would restore the boot but re-break telephony.
PRODUCT_PACKAGES += \
    android.frameworks.sensorservice-V1-ndk.vendor \
    android.hardware.sensors-V2-ndk.vendor


# QTI display AIDL interface libraries, vendor variants.
#
# These are not display features -- they are here because BOOT depends on one of
# them. qseecomd's listener manager dlopen()s /vendor/lib64/libops.so, which
# links vendor.qti.hardware.display.config-V7-ndk.so:
#
#   E ListenerMngr: Init dlopen(libops.so, RLTD_NOW) is failed....
#       dlopen failed: library "vendor.qti.hardware.display.config-V7-ndk.so"
#       not found: needed by /vendor/lib64/libops.so
#   E QSEECOMD: : ERROR: Failed to start listner services.
#
# and qseecomd then exits 255, which takes the whole TEE chain down with it.
#
# Note this class of failure is invisible to a DT_NEEDED walk from the service
# binary, because libops.so is reached by dlopen, not by a link-time dependency.
# It was found by sweeping every ELF in the vendor image for unresolved
# DT_NEEDED entries; that sweep is the tool to reach for when a vendor process
# dies instantly with no useful message.
#
# The other versions are shipped for the same reason and were found by the same
# sweep -- V5 alone is needed by ten vendor libraries (libqti-perfd, qguard,
# libqcodec2_utils, the *optfeature ones, libwfddisplayconfig_vendor ...). The
# AIDL interface is frozen with versions 1-15 and is vendor_available, so each
# version builds from vendor/qcom/opensource/commonsys-intf/display/aidl.
# peridot ships these exactly this way (its device.mk lists
# vendor.qti.hardware.display.config-V11-ndk.vendor).
PRODUCT_PACKAGES += \
    vendor.qti.hardware.display.config-V2-ndk.vendor \
    vendor.qti.hardware.display.config-V5-ndk.vendor \
    vendor.qti.hardware.display.config-V7-ndk.vendor \
    vendor.qti.hardware.display.config-V11-ndk.vendor

# composer3: the stock composer binary links android.hardware.graphics.composer3-V2
# and vendor.qti.hardware.display.composer3-V1 while the platform settles on V3/V4.
# Both are aidl_interface-generated, so they are built here rather than shipped as
# prebuilts (a prebuilt of the same name fails with "partition is different").
PRODUCT_PACKAGES += \
    android.hardware.graphics.composer3-V2-ndk.vendor \
    vendor.qti.hardware.display.composer3-V1-ndk.vendor

PRODUCT_PACKAGES += \
    vendor.qti.hardware.display.color-V1-ndk.vendor \
    vendor.qti.hardware.display.demura-V1-ndk.vendor \
    vendor.qti.hardware.display.postproc-V1-ndk.vendor

# The /vendor mount points the fstab needs (see sm8635-common/Android.bp).
# These come from the build now, so workspace/inject-vendor-mountpoints.sh --
# a post-`mka vendorimage` step that silently reintroduced a fatal defect if
# forgotten -- is no longer required.
PRODUCT_PACKAGES += \
    vendor_bt_firmware_mountpoint \
    vendor_dsp_mountpoint \
    vendor_firmware_mnt_mountpoint \
    vendor_fsg_mountpoint


# VINTF fragments. These must NOT go in sm8635-common/manifest.xml: that file is
# dead code here, because libvintf reads manifest_${ro.boot.product.vendor.sku}.xml
# and returns without ever falling back (stock ships no manifest.xml at all).
# Fragments under /vendor/etc/vintf/manifest/ are always merged.
# ENABLED as of bc23. It was disabled because declaring android.hardware.sensors
# while the multihal could not register recreated the weaver bug exactly: something
# blocked in waitForDeclaredService and Watchdog killed system_server every 65s.
# The gating condition was "re-enable ONLY after the multihal is proven to
# register". That condition is now MET, and bc22 is the proof:
#
#   - 134ca03 gave hal_sensors_default binder_call to hal_graphics_composer_default,
#     which killed the ISensorExt empty-descriptor SIGSEGV. bc22 has ZERO
#     'associateClass ... descriptor is actually' errors (bc21 had 95).
#   - The multihal now runs all the way to its registration call and dies THERE,
#     on nothing but the missing declaration:
#         Abort message: 'Check failed: status == STATUS_OK (status=-3, STATUS_OK=0)'
#         #03 android.hardware.sensors-service.multihal (main.cfi+3328)
#     -3 is EX_ILLEGAL_ARGUMENT from addService() via meetsDeclarationRequirements():
#     a name starting with "android.hardware." that is not VINTF-declared cannot be
#     registered. Confirmed: android.hardware.sensors appears nowhere under
#     out/.../vendor/etc/vintf/.
#
# So the declaration is now the ONLY thing rejecting a service that otherwise
# reaches addService -- the opposite of the situation that justified disabling it.
#
# The old note here also blamed a "SIGABRT in SensorExt::initAlsComp". That is
# FALSIFIED: vendor.moto_sensorext starts once, never aborts and never restarts;
# it registered fine and simply could not be called into.
PRODUCT_PACKAGES += \
    android.hardware.sensors-arcfox.xml

# Codec2 IComponentStore declarations. Without this fragment there is no
# `default` store in the device manifest, vendor.qti.media.c2@1.0-service
# crash-loops, and the device silently runs on software codecs only.
PRODUCT_PACKAGES += \
    manifest_media_c2.xml


# adb. init.mmi.usb.rc blanks persist.sys.usb.config at load-bpf-programs and the
# script that restores it (/vendor/bin/init.mmi.usb.sh) cannot run because it is
# unlabelled, so the UDC is never bound and the device NEVER enumerates on USB in
# Android. This rc restores it at early-boot -- after the blanking, before
# `on boot` reads it. Full mechanism in the file.
PRODUCT_PACKAGES += \
    init.arcfox-usb.rc


# WiFi. The HAL binary and all its dependencies are already shipped and the
# qca_cld3_kiwi_v2 driver is loaded, but nothing started the service. This rc
# does. Both landed and IWifi/default now registers.
#
# android.hardware.wifi-V1-ndk.vendor is the version Motorola COMPILED the HAL
# against. We used to relink the blob to V4 instead; it registered and then
# SIGABRTed inside the V4 NDK backend the first time the framework touched
# IWifiStaIface (free() on a 0x3 pointer). Same rule, and the same fix, as the
# keymint V2/V3 pair above: ship the version the blob expects, never rewrite its
# DT_NEEDED. Details in extract-files.py and vintf/android.hardware.wifi-arcfox.xml.
PRODUCT_PACKAGES += \
    init.arcfox-wifi.rc \
    android.hardware.wifi-arcfox.xml \
    android.hardware.wifi-V1-ndk.vendor

# wpa_supplicant, built from source (see the Wi-Fi block in BoardConfigCommon.mk
# for why the Motorola blob is unusable). The Soong module installs to the same
# path the blob used, /vendor/bin/hw/wpa_supplicant, and brings its own init rc
# and its own VINTF fragment for ISupplicant/default -- so, unlike a blob, the
# binary, the rc and the manifest entry cannot drift apart. (The fragment installs
# as version 4, not 5: assemble_vintf clamps it to the latest frozen version. FCM
# 202504 asks for supplicant 3-4, so 4 is in range.)
#
# lib_driver_cmd_qcwcn is selected by BOARD_WPA_SUPPLICANT_PRIVATE_LIB and gives
# the QCA vendor driver commands the framework expects.
#
# wpa_supplicant.conf must be listed explicitly. It is qcwcn's prebuilt_etc
# (generated from AOSP's template by :wpa_supplicant_conf_gen) and it took the
# place of the Motorola blob conf we dropped -- but nothing pulls it in on its
# own, and without it /vendor/etc/wifi/wpa_supplicant.conf simply does not ship.
# That does not fail this device today only because /data/vendor/wifi/wpa/
# already holds a copy from an earlier boot; on a clean flash or after a data
# wipe the supplicant would have no template to seed from.
PRODUCT_PACKAGES += \
    wpa_supplicant \
    wpa_supplicant.conf

# hostapd, also from source, for SoftAP / Wi-Fi tethering. The Motorola blob was
# shipped all along but could never exec (sk_dup again), so IHostapd/default has
# never registered and every tethering attempt failed at
# numSetupSoftApInterfaceFailureDueToHostapd.
#
# Only the binary is listed. Unlike the supplicant, hostapd needs no companion
# entries: its cc_binary declares init_rc and vintf_fragment_modules directly, so
# the rc and the IHostapd/default declaration come with it, and there is no
# hostapd.conf -- the AIDL HAL is handed the AP parameters by the framework and
# writes the config itself into /data/vendor/wifi/hostapd.
#
# The module only exists if BOARD_HOSTAPD_DRIVER is set; see BoardConfigCommon.mk.
PRODUCT_PACKAGES += \
    hostapd

# Wi-Fi capability RRO. Without it the framework believes this is a 2.4 GHz-only
# radio, because AOSP defaults config_wifi5ghzSupport and config_wifi6ghzSupport
# to false and this tree shipped no Wi-Fi overlay at all. STA mode never noticed
# -- the device associates on 5 GHz regardless -- but SoftAP consults only those
# resources and refused any band but 2.4. Evidence per resource is in the overlay's
# own config.xml, and the reason it is an RRO rather than a static overlay is in
# its Android.bp.
#
# KNOWN LIMITATION, and it is not this overlay's fault: 5 GHz and 6 GHz SoftAP
# additionally require a Wi-Fi country code, which THIS ROM CANNOT OBTAIN TODAY
# because the modem does not come up, so WifiCountryCode gets an empty string
# from telephony. 5 GHz is an explicit refusal in
# ApConfigUtil.updateApChannelConfig ("5GHz band is not allowed without country
# code"); 6 GHz fails indirectly, because the driver reports no usable channels
# for the band. Until telephony works, the hotspot is 2.4 GHz-only. All three
# bands were proven to work by forcing a code with `cmd wifi force-country-code
# enabled <CC>` -- which is an in-memory override that does NOT survive a reboot.
#
# DELIBERATELY NOT hardcoding a default country code here. It is a regulatory
# decision rather than a technical one, one image is used across regions, and
# 6 GHz is exactly the band where regions diverge most, so a wrong value does
# the most damage precisely where this overlay adds capability. If a default is
# ever wanted it should be an explicit, documented opt-in via
# androidboot.wificountrycode=XX on BOARD_KERNEL_CMDLINE, which WifiCountryCode
# reads as ro.boot.wificountrycode and which telephony still overrides.
PRODUCT_PACKAGES += \
    SM8635WifiOverlay


# NFC. Everything already ships -- the ST HAL, nfc_nci.st21nfc.st.so, both
# firmware blobs, all libnfc-hal-st*.conf, the SELinux labels -- and
# INfc/default is ALREADY VINTF-declared. Only ro.vendor.hw.nfc (see vendor.prop)
# and a usable start trigger were missing, so servicemanager retried
# tryStartService once a second forever. Verified live before shipping: started
# by hand, the HAL registers and exchanges real NCI frames with the chip.
PRODUCT_PACKAGES += \
    init.arcfox-nfc.rc


# Bluetooth audio HAL. Without it com.android.bluetooth HARD-ABORTS on every
# enable attempt, which is the flashing BT toggle:
#   F bluetooth: LE Audio Client requires Bluetooth Audio HAL V2.1 at least.
#                Either disable LE Audio Profile, or update your HAL
#   E bluetooth: HalVersionManager: No supported HAL version
#   BluetoothSystemServer: requested to [Disable]. Reason is CRASH
# LE_AUDIO is enabled by default and the check is LOG_ALWAYS_FATAL. The vendor
# only provides the QTI-specific HIDL vendor.qti.hardware.bluetooth_audio@2.1;
# nothing declares the AOSP AIDL
# android.hardware.bluetooth.audio.IBluetoothAudioProviderFactory/default.
# This module is AOSP's own software implementation and brings its own vintf
# fragment, so it is a plain device-tree omission rather than a blob problem.
#
# NOTE this does not turn Bluetooth on by itself: the stack also wants an AIDL
# android.hardware.bluetooth.IBluetoothHci, while stock declares only the HIDL
# @1.1 one. That still needs an AIDL BT HAL built over the QTI transport.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth.audio-impl

# The CLASSIC Bluetooth profiles. Without these the stack has no A2DP/HFP/AVRCP
# at all, so a speaker or headset PAIRS and then cannot connect -- Settings just
# logs, once, and never even attempts:
#
#   D CachedBluetoothDevice: No profiles. Maybe we will connect later for device ...
#
# Stock sets all 14 in /product/etc/build.prop (lines 104-118). LineageOS
# rebuilds the product partition from scratch, so they were lost -- exactly the
# same shape as the data-plane props in eb182d2. What we DID keep are the eight
# LE-audio ones (bap/ccp/csip/hap/mcp/vcp), because those come from vendor.prop
# and so ride along on /vendor/build.prop. Nothing in LineageOS supplies these
# for a real device; only goldfish, cuttlefish and Car set them, so it is the
# device tree's job.
#
# Verified live before committing: with the properties set by hand and
# com.android.bluetooth force-stopped so it re-read them, the same tap that had
# produced "No profiles" instead produced a real connection attempt --
#   I BluetoothAdapterService: connectEnabledProfile: Connecting A2dpService
#   I A2dpService: okToConnect: device ... isOutgoingRequest: true
#   D CachedBluetoothDevice: onProfileStateChanged: profile A2DP, newProfileState 1
# It then went back to state 0 after ~10s, which is the timeout signature of the
# speaker being powered off/out of range rather than a stack fault; that half
# still needs confirming with the speaker switched on.
#
# Taken verbatim from stock, including hid.device being the one set to false.
PRODUCT_PRODUCT_PROPERTIES += \
    bluetooth.profile.a2dp.source.enabled=true \
    bluetooth.profile.avrcp.target.enabled=true \
    bluetooth.profile.avrcp.controller.enabled=true \
    bluetooth.profile.hfp.ag.enabled=true \
    bluetooth.profile.gatt.enabled=true \
    bluetooth.profile.hid.host.enabled=true \
    bluetooth.profile.hid.device.enabled=false \
    bluetooth.profile.map.server.enabled=true \
    bluetooth.profile.opp.enabled=true \
    bluetooth.profile.pan.nap.enabled=true \
    bluetooth.profile.pan.panu.enabled=true \
    bluetooth.profile.pbap.server.enabled=true \
    bluetooth.profile.bas.client.enabled=true \
    bluetooth.profile.asha.central.enabled=true

$(call inherit-product-if-exists, vendor/motorola/sm8635-common/sm8635-common-vendor.mk)

# FACE UNLOCK. Everything needed was already on the device except the exec label:
# both stock binaries, stock's init rc and the libFace3D set are extracted, the V3
# NDK interface libraries are source-built, and the binary's full 79-library
# closure resolves with nothing missing. (The libFace3D*.so are the LEGACY HIDL
# HAL's, not this one's -- neither binary imports dlopen.) init was
# simply refusing to start the HAL because the binary is labelled vendor_file --
# proven live with `start biometrics-face-hal`, which returns the same
# "no domain transition from u:r:init:s0" error as the Motorola service family.
#
# The label lives in sepolicy/vendor/file_contexts; these two files are the other
# half and must not ship without it. See vintf/android.hardware.biometrics.face-arcfox.xml
# for why the declaration is version 3, and why declaring it early is harmful.
PRODUCT_PACKAGES += \
    android.hardware.biometrics.face-arcfox.xml \
    android.hardware.biometrics.face.xml

# THE MODEM'S REMOTE FILE SYSTEM NAMESPACE -- the telephony root cause.
#
# /vendor/bin/tftp_server serves files to the modem, ADSP, CDSP and SLPI over QMI,
# and its ten server roots are COMPILED IN, pointing at /vendor/rfs/{msm,mdm,apq}/*.
# The modem asks for paths relative to those roots. Stock resolves them with a farm
# of symlinks redirecting readwrite -> the persist partition, readonly -> the
# firmware mounts, ramdumps -> tombstones.
#
# /vendor/rfs DID NOT EXIST ON THIS PORT AT ALL, so the modem could not read
# /readwrite/cal_rfs/rf000296*.bin -- 180 KiB of per-unit RF calibration written at
# the factory on 2024-06-06 (430,650 B for all seven rf*.bin in that directory).
# The modem reports init failure with reason "no calibration" and qcril turns that
# into RADIO_POWER error 71 / NO_RF_CALIBRATION_INFO.
#
# The modules were in the tree all along: hardware/qcom-caf/common/Android.bp has
# all 84 of them. This device tree just never listed them. We take the names rather
# than $(call inherit-product, hardware/qcom-caf/common/common.mk) because that file
# also adds PRODUCT_VENDOR_LINKER_CONFIG_FRAGMENTS, and the linker namespace layout
# on this port is load-bearing for the vendor blobs.
#
# The two /vendor/rfs/msm/mpss/readonly/*fsg links upstream lacks are in rfs/Android.bp.
PRODUCT_PACKAGES += \
    rfs_apq_gnss_hlos_symlink \
    rfs_apq_gnss_ramdumps_symlink \
    rfs_apq_gnss_readonly_firmware_symlink \
    rfs_apq_gnss_readonly_vendor_firmware_symlink \
    rfs_apq_gnss_readwrite_symlink \
    rfs_apq_gnss_shared_symlink \
    rfs_mdm_adsp_hlos_symlink \
    rfs_mdm_adsp_ramdumps_symlink \
    rfs_mdm_adsp_readonly_firmware_symlink \
    rfs_mdm_adsp_readonly_vendor_firmware_symlink \
    rfs_mdm_adsp_readwrite_symlink \
    rfs_mdm_adsp_shared_symlink \
    rfs_mdm_cdsp_hlos_symlink \
    rfs_mdm_cdsp_ramdumps_symlink \
    rfs_mdm_cdsp_readonly_firmware_symlink \
    rfs_mdm_cdsp_readonly_vendor_firmware_symlink \
    rfs_mdm_cdsp_readwrite_symlink \
    rfs_mdm_cdsp_shared_symlink \
    rfs_mdm_mpss_hlos_symlink \
    rfs_mdm_mpss_ramdumps_symlink \
    rfs_mdm_mpss_readonly_firmware_symlink \
    rfs_mdm_mpss_readonly_vendor_firmware_symlink \
    rfs_mdm_mpss_readwrite_symlink \
    rfs_mdm_mpss_shared_symlink \
    rfs_mdm_ois_hlos_symlink \
    rfs_mdm_ois_ramdumps_symlink \
    rfs_mdm_ois_readonly_firmware_symlink \
    rfs_mdm_ois_readonly_vendor_firmware_symlink \
    rfs_mdm_ois_readwrite_symlink \
    rfs_mdm_ois_shared_symlink \
    rfs_mdm_slpi_hlos_symlink \
    rfs_mdm_slpi_ramdumps_symlink \
    rfs_mdm_slpi_readonly_firmware_symlink \
    rfs_mdm_slpi_readonly_vendor_firmware_symlink \
    rfs_mdm_slpi_readwrite_symlink \
    rfs_mdm_slpi_shared_symlink \
    rfs_mdm_tn_hlos_symlink \
    rfs_mdm_tn_ramdumps_symlink \
    rfs_mdm_tn_readonly_firmware_symlink \
    rfs_mdm_tn_readonly_vendor_firmware_symlink \
    rfs_mdm_tn_readwrite_symlink \
    rfs_mdm_tn_shared_symlink \
    rfs_mdm_wpss_hlos_symlink \
    rfs_mdm_wpss_ramdumps_symlink \
    rfs_mdm_wpss_readonly_firmware_symlink \
    rfs_mdm_wpss_readonly_vendor_firmware_symlink \
    rfs_mdm_wpss_readwrite_symlink \
    rfs_mdm_wpss_shared_symlink \
    rfs_msm_adsp_hlos_symlink \
    rfs_msm_adsp_ramdumps_symlink \
    rfs_msm_adsp_readonly_firmware_symlink \
    rfs_msm_adsp_readonly_vendor_firmware_symlink \
    rfs_msm_adsp_readwrite_symlink \
    rfs_msm_adsp_shared_symlink \
    rfs_msm_cdsp_hlos_symlink \
    rfs_msm_cdsp_ramdumps_symlink \
    rfs_msm_cdsp_readonly_firmware_symlink \
    rfs_msm_cdsp_readonly_vendor_firmware_symlink \
    rfs_msm_cdsp_readwrite_symlink \
    rfs_msm_cdsp_shared_symlink \
    rfs_msm_mpss_hlos_symlink \
    rfs_msm_mpss_ramdumps_symlink \
    rfs_msm_mpss_readonly_firmware_symlink \
    rfs_msm_mpss_readonly_vendor_firmware_symlink \
    rfs_msm_mpss_readwrite_symlink \
    rfs_msm_mpss_shared_symlink \
    rfs_msm_ois_hlos_symlink \
    rfs_msm_ois_ramdumps_symlink \
    rfs_msm_ois_readonly_firmware_symlink \
    rfs_msm_ois_readonly_vendor_firmware_symlink \
    rfs_msm_ois_readwrite_symlink \
    rfs_msm_ois_shared_symlink \
    rfs_msm_slpi_hlos_symlink \
    rfs_msm_slpi_ramdumps_symlink \
    rfs_msm_slpi_readonly_firmware_symlink \
    rfs_msm_slpi_readonly_vendor_firmware_symlink \
    rfs_msm_slpi_readwrite_symlink \
    rfs_msm_slpi_shared_symlink \
    rfs_msm_wpss_hlos_symlink \
    rfs_msm_wpss_ramdumps_symlink \
    rfs_msm_wpss_readonly_firmware_symlink \
    rfs_msm_wpss_readonly_vendor_firmware_symlink \
    rfs_msm_wpss_readwrite_symlink \
    rfs_msm_wpss_shared_symlink \
    rfs_msm_mpss_readonly_fsg \
    rfs_msm_mpss_readonly_vendor_fsg
