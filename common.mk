# Common makefile for Motorola SM8635 (pineapple).

COMMON_PATH := device/motorola/sm8635-common

PRODUCT_SOONG_NAMESPACES += $(COMMON_PATH)

# These directories declare their own Soong namespaces, so their modules are
# invisible -- PRODUCT_PACKAGES entries for them fail as "non-existent modules"
# -- until they are listed here.
#   hardware/qcom-caf/bootctrl                    android.hardware.boot-service.qti
#   vendor/qcom/opensource/commonsys-intf/display the vendor.qti.hardware.display.*
#                                                 AIDL interfaces
PRODUCT_SOONG_NAMESPACES += hardware/qcom-caf/bootctrl
PRODUCT_SOONG_NAMESPACES += vendor/qcom/opensource/commonsys-intf/display

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
# Deliberately EXCLUDES vendor_boot, vendor_dlkm, system_dlkm and dtbo: this ROM
# does not build them (prebuilt GKI kernel, stock kernel modules), so the stock
# copies must be left untouched on the handset.
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    product \
    system \
    system_ext \
    vbmeta \
    vendor

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
# NOT ENABLED YET. Declaring android.hardware.sensors while the multihal cannot
# actually register it recreates the weaver bug exactly: something blocks in
# waitForDeclaredService (718 'Waited one second for
# android.hardware.sensors.ISensors/default') and Watchdog kills system_server
# ('Blocked in handler on main thread (main) for 65s'). The boot regressed from
# 'completes setup' to 'never boots' the moment this was added.
#
# Undeclared is strictly better than declared-but-unstartable: with it absent,
# SensorService simply has no sensors and the device boots.
#
# Re-enable ONLY after the multihal is proven to register, which needs the
# sensorext SIGABRT in SensorExt::initAlsComp fixed first -- the multihal blocks
# waiting on motorola.hardware.sensors.ISensorExt/default, so it never finishes
# init and never calls addService.
# PRODUCT_PACKAGES += \
#     android.hardware.sensors-arcfox.xml


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

$(call inherit-product-if-exists, vendor/motorola/sm8635-common/sm8635-common-vendor.mk)
