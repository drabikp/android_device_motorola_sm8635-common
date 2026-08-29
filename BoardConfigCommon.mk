#
# Common BoardConfig for Motorola SM8635 (Snapdragon 8s Gen 3, "pineapple").
#
# FIRST DRAFT, but not a guessed one. Every value below was measured on a real
# arcfox running W1UXS36H.72-45-10-7 (Android 16), or read out of that build's
# firmware package with avbtool / unpack_bootimg. Anything still uncertain is
# marked UNVERIFIED rather than left to look authoritative.
#
# Tree naming: sm8635-common, not sm8650-common. The SoC is SM8635 and
# LineageOS names common trees after the SoC (cf. LineageOS/android_kernel_
# xiaomi_sm8635). Motorola-Pineapple used "sm8650-common" because SM8635 shares
# Qualcomm's "pineapple" platform with SM8650, but that tree is a 7-file stub
# with no kernel wiring, so there is nothing to stay compatible with.
#

COMMON_PATH := device/motorola/sm8635-common

# Platform. ro.board.platform reads "pineapple" on-device.
TARGET_BOARD_PLATFORM := pineapple
TARGET_NO_BOOTLOADER := true

# Architecture. Cortex-X4 + A720 + A520.
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a76

# No TARGET_2ND_ARCH: this device is 64-bit only (see lineage_arcfox.mk).
TARGET_SUPPORTS_32_BIT_APPS := false
TARGET_SUPPORTS_64_BIT_APPS := true

# --- Kernel -----------------------------------------------------------------
# GKI 2.0, prebuilt. boot.img unpacks to kernel-only (ramdisk size 0, header
# v4); the ramdisk is in init_boot.img and the vendor ramdisk in
# vendor_boot.img. Every device driver ships as a prebuilt module: 287 in
# vendor_dlkm, 60 in system_dlkm.
#
# There is NO usable Motorola kernel source for this device. Checked, not
# assumed:
#   Motorola-Pineapple/android_kernel_motorola_sm8650   -> EMPTY repo, size 0
#   Kendrenogen-moto-sm8635-6-6/..._motorola_sm8635     -> kernel 6.6.82
# and this device runs the 6.1 android14 GKI line, so 6.6 is the wrong branch.
#
# KERNEL: BUILT FROM SOURCE via vendor/lineage/build/tasks/kernel.mk
# (Route A, peridot/sm8550-common shape -- see HANDOFF-NEXT.md 0.26/0.28).
#
# History: until 2026-08-28 this shipped a PREBUILT Google GKI Image plus 287
# prebuilt vendor_dlkm/.60 system_dlkm .ko -- a hard blocker for official
# LineageOS (charter: "MUST build all feasible modules from source"; census:
# 0 committed .ko across all 310 official devices). The kernel tree is
# MotorolaMobilityLLC/kernel-msm @ MMI-W1UXS36H.72-45-4-1 merged forward to
# ACK android14-6.1-2025-09_r34 (same certified 6.1.145 family the device
# ran on the prebuilt; KMI-invisible: 20,475 CRC matches / 0 mismatches vs
# the shipped module set). TARGET_NO_KERNEL_OVERRIDE (a GSI/Cuttlefish-only
# variable; 0 physical devices upstream) is GONE -- kernel.mk now runs.
TARGET_KERNEL_SOURCE := kernel/motorola/sm8635
TARGET_KERNEL_CONFIG := \
    gki_defconfig \
    vendor/pineapple_GKI.config \
    vendor/ext_config/moto-pineapple.config \
    vendor/ext_config/moto-pineapple-arcfox.config \
    vendor/ext_config/arcfox-signing.config
# clang-r547379 (clang 20): the Motorola tree predates clang-21-only warnings.
# KCFLAGS demotes 27 pre-existing printk-format sites in Motorola's own code
# (walt.c, gunyah, mhi, qcom-pdc, af_qrtr) that -Werror would fatalize.
TARGET_KERNEL_CLANG_VERSION := r547379
# Use the HOST glibc for kernel host tools, not AOSP's 2.17 sysroot: with the
# old sysroot, host tools compiled against modern headers fail to link
# (undefined __isoc23_strtol).
TARGET_KERNEL_LIBC_SYSROOT_USE := host

# ⚠️ These REPLACE the HOSTCFLAGS/HOSTLDFLAGS that BoardConfigKernel.mk sets --
# TARGET_KERNEL_ADDITIONAL_FLAGS lands later on the make command line, so a
# partial override silently drops the whole upstream value (that is what broke
# the first attempt: it removed the OpenSSL include AND the sysroot at once).
# Deliberately NOT pointing at prebuilts/kernel-build-tools: its BoringSSL
# libcrypto REFUSES sha256 module signing ("only supports SHA1 signing"), and
# our signing fragment requires sha256. Host OpenSSL 3.x does both, and the
# r34 merge fixed certs/extract-cert.c so it compiles against it cleanly.
# -Wno-...-discards-qualifiers: tools/lib/bpf/libbpf.c:10746 still assigns a
# const char * to char * and host clang makes that an error.
# KCFLAGS=-Wno-error (not just =format): this Jan-2026 vendor tree predates
# the toolchain, and several subtrees carry warnings that newer clang
# fatalizes -- printk formats in walt/gunyah/mhi/qcom-pdc/af_qrtr, and
# -Wenum-compare in dataipa ipa_usb.c. Demoting warnings-as-errors does not
# hide actual errors, and mirrors what the standalone module builds used.
TARGET_KERNEL_ADDITIONAL_FLAGS := TARGET_PRODUCT=$(PRODUCT_DEVICE) \
    KCFLAGS=-Wno-error \
    LLVM=1 LLVM_IAS=1 \
    HOSTCFLAGS="-Wno-error -Wno-incompatible-pointer-types-discards-qualifiers" \
    HOSTLDFLAGS="-fuse-ld=lld --rtlib=compiler-rt" \
    TARGET_BOARD_PLATFORM=$(TARGET_BOARD_PLATFORM)

# External modules, DEPENDENCY ORDER (symvers chains -- see the per-module
# Makefile "arcfox kernel.mk port" blocks and build-kernel-modules.sh):
# securemsm before camera/display/bt; mm-drivers before graphics; dsp+synx
# before eva; mmrm before video/camera; datarmnet-ext/mem then dataipa then
# datarmnet/core then the ext family; sensors/mmi_relay/mmi_info/display
# before touchscreen_mmi before the panel drivers; chargers chain bm_adsp ->
# qti_glink -> rest.
# NOT LISTED: moto_swap (kernel-side hybridswap unpublished -- prebuilt
# exception), qcacld (WLAN: built out-of-band pending source resolution,
# HANDOFF-NEXT 0.28).
TARGET_KERNEL_EXT_MODULE_ROOT := kernel/motorola/sm8635-modules
TARGET_KERNEL_EXT_MODULES := \
    qcom/opensource/mmrm-driver \
    qcom/opensource/securemsm-kernel \
    qcom/opensource/mm-drivers/hw_fence \
    qcom/opensource/mm-drivers/msm_ext_display \
    qcom/opensource/mm-drivers/sync_fence \
    qcom/opensource/synx-kernel \
    qcom/opensource/dsp-kernel \
    qcom/opensource/eva-kernel \
    qcom/opensource/mm-sys-kernel/ubwcp \
    qcom/opensource/display-drivers/msm \
    qcom/opensource/graphics-kernel \
    qcom/opensource/video-driver \
    qcom/opensource/camera-kernel \
    qcom/opensource/audio-kernel \
    qcom/opensource/wlan/platform \
    qcom/opensource/wlan/qcacld-3.0/.kiwi_v2 \
    qcom/opensource/bt-kernel \
    qcom/opensource/datarmnet-ext/mem \
    qcom/opensource/dataipa/drivers/platform/msm \
    qcom/opensource/datarmnet/core \
    qcom/opensource/datarmnet-ext/aps \
    qcom/opensource/datarmnet-ext/offload \
    qcom/opensource/datarmnet-ext/shs \
    qcom/opensource/datarmnet-ext/perf \
    qcom/opensource/datarmnet-ext/perf_tether \
    qcom/opensource/datarmnet-ext/sch \
    qcom/opensource/datarmnet-ext/wlan \
    nxp/opensource/driver \
    motorola/drivers/misc/utag \
    motorola/drivers/mmi_annotate \
    motorola/drivers/mmi_info \
    motorola/drivers/mmi_relay \
    motorola/drivers/mmi_qcom_minidump \
    motorola/drivers/misc/mmi_sys_temp \
    motorola/drivers/sensors \
    motorola/drivers/moto_con_dfpar \
    motorola/drivers/moto_binder \
    motorola/drivers/moto_mmap_fault \
    motorola/drivers/moto_reboot_reason \
    motorola/drivers/moto_f_usbnet \
    motorola/drivers/moto_sched \
    motorola/drivers/power/cw2217b_fg_mmi \
    motorola/drivers/power/mmi_charger \
    motorola/drivers/power/bm_adsp_ulog \
    motorola/drivers/power/qti_glink_charger \
    motorola/drivers/power/sc760x_charger_mmi \
    motorola/drivers/power/qpnp_adaptive_charge \
    motorola/drivers/power/mmi_lpd_mitigate \
    motorola/drivers/input/misc/fpc_fps_mmi \
    motorola/drivers/input/misc/anc_fps_mmi \
    motorola/drivers/input/misc/goodix_fod_mmi \
    motorola/drivers/input/touchscreen/touchscreen_mmi \
    motorola/drivers/input/touchscreen/focaltech_touch_v3_5 \
    motorola/drivers/input/touchscreen/goodix_berlin_mmi \
    motorola/drivers/input/touchscreen/goodix_gt96x_mmi \
    motorola/drivers/ese/st54spi_gpio \
    motorola/drivers/misc/mmi_stow \
    motorola/drivers/misc/suspend_marker \
    motorola/drivers/misc/sx937x_multi \
    motorola/drivers/regulator/wl2868c \
    motorola/drivers/watchdogtest \
    motorola/drivers/nfc/st21nfc
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_KERNEL_ARCH := arm64
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_BOOT_HEADER_VERSION := 4
# init_boot is a separate image on GKI devices and needs its own header
# version, otherwise soong's filesystem generator fails with
# "lineage_arcfox_generated_init_boot_image ... header_version: must be set".
BOARD_INIT_BOOT_HEADER_VERSION := 4
BOARD_RAMDISK_USE_LZ4 := true
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

# NOTE: `androidboot.selinux=permissive` was added here as a diagnostic and has
# been REMOVED. The flag genuinely reached the kernel (confirmed in the bootargs
# of logfs Log69.txt) and the device still hung.
#
# CORRECTION: that did NOT rule SELinux out, and saying so here was wrong.
#   1. init/service.cpp makes a missing domain transition fatal only when
#      ENFORCING -- under permissive it logs and starts the service anyway. So
#      the test masked precisely the failure mode we now suspect.
#   2. It was run when vendor shipped 15 HAL binaries. The current build ships
#      68, and has never been tested under permissive at all.
# See the SELinux vendor policy section at the end of this file.
#
# Do NOT re-add it to a build anyone else flashes: it disables SELinux
# enforcement device-wide. If it is needed again for debugging, remove it before
# publishing anything.
#
# (We do still ship zero device sepolicy, which will cause denials and broken
# functionality once the ROM boots -- see BOARD_VENDOR_SEPOLICY_DIRS in zeekr.)

# BOARD_INIT_BOOT_HEADER_VERSION above only satisfies soong's filesystem
# generator. It never reaches mkbootimg: build/make/core/Makefile builds
# init_boot from INTERNAL_INIT_BOOT_IMAGE_ARGS + INTERNAL_MKBOOTIMG_VERSION_ARGS
# + BOARD_MKBOOTIMG_INIT_ARGS, and none of those carry --header_version. The
# result was a v0 header, which Motorola's bootloader rejects outright --
# every `fastboot flash init_boot` failed with "Preflash validation failed"
# while stock's flashed fine. Measured with unpack_bootimg.py:
#
#                 header version    os_version
#   stock         4                 None
#   ours (bad)    0                 16.0.0
#
# Same class of defect as the recovery kernel_size bug: the image was well
# formed, just structurally unlike what this bootloader accepts. os_version is
# zeroed to match stock, exactly as done for recovery above.
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_INIT_BOOT_HEADER_VERSION) \
    --os_version 0 --os_patch_level 0

# Sizes read from the shipping firmware package.
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
# vendor_boot IS now rebuilt. It used to be left stock, which avoided needing a
# vendor_ramdisk staging dir, but that shortcut is the leading suspect for the
# remaining first-stage-init failure: stock's vendor_ramdisk carries Motorola's
# own first_stage_ramdisk layout, modules.load and dtb, all authored for
# Motorola's init, and we drive it with LineageOS's init from init_boot.
# Every shipping LineageOS device (incl. zeekr, the official Razr 40 Ultra port)
# builds its own vendor_boot.
#
# The staging dir is populated from BOARD_VENDOR_RAMDISK_KERNEL_MODULES below,
# which is what the old "panic: lstat .../vendor_ramdisk: no such file" was
# really complaining about.
#
# Contents replicated from stock vendor_boot.img (unpack_bootimg):
#   header v4, page size 0x1000, ramdisk load 0x01000000
#   vendor ramdisk 8,172,748 bytes -> lib/modules (282 .ko) + first_stage_ramdisk
#   dtb 469,389 bytes at 0x01f00000
#   partition size 100,663,296
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296

# dtb lives in vendor_boot on header v3+, not in boot.img. Taken verbatim from
# stock vendor_boot -- we do not build a kernel, so we cannot regenerate it.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(COMMON_PATH)/prebuilt/dtb

# Motorola's prebuilt first-stage modules, lifted from stock's vendor_ramdisk.
# modules.load (99 entries) is stock's and fixes load ORDER, which matters.
# BOARD_VENDOR_RAMDISK_KERNEL_MODULES: now populated by kernel.mk (load list below)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(strip $(shell cat $(COMMON_PATH)/modules/modules.list.vendor_ramdisk 2>/dev/null))

# RECOVERY loads a different, larger set (277 entries vs 99). Omitting this is
# what broke TWRP: with our first vendor_boot, TWRP -- a known-good recovery
# ramdisk that boots fine on stock vendor_boot -- stopped booting entirely.
# That makes "does TWRP still boot?" a fast sanity check on vendor_boot.
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(strip $(shell cat $(COMMON_PATH)/modules/modules.list.recovery 2>/dev/null))

# Qualcomm's blocklist (62 entries: test/torture modules, unused tuners,
# qca_cld3_kiwi, vsock...). Without it those modules load anyway, which stock
# deliberately prevents.
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := $(COMMON_PATH)/modules/modules.blocklist.ramdisk

# Verbatim from stock vendor_boot's bootconfig and vendor cmdline. androidboot.*
# must go in BOARD_BOOTCONFIG (bootconfig section), the rest in the cmdline.
# SELINUX IS RULED OUT -- the permissive test was RUN and is CONCLUSIVE.
#
# `androidboot.selinux=permissive` was re-added as a diagnostic and has been
# removed again. Unlike the earlier attempt (which ran with 15 HAL binaries and
# proved nothing), this one was a real test, on the current 68-HAL vendor, and
# the flag was verifiably active: 122 AVC denials were logged versus 6 under
# enforcing.
#
# Result: the boot hangs IDENTICALLY. keymint-qti's /proc state is unchanged --
# main thread in futex_wait_queue, four threads parked in smcinvoke_ioctl. And
# not one of the 122 denials involves keymint, tee, qseecom or smcinvoke.
#
# This matters because permissive also neutralises `dontaudit`, which ENFORCES a
# denial while suppressing its log line -- the one way a policy gap could have
# caused a silent hang. It did not. Do not spend time on SELinux for this bug.
# The captured denial list is in workspace/permissive-denials.txt; it is the
# work-list for sepolicy/vendor once the ROM boots, not a set of blockers.
BOARD_BOOTCONFIG += \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.usbcontroller=a600000.dwc3 \
    androidboot.load_modules_parallel=true \
    androidboot.hypervisor.protected_vm.supported=false \
    androidboot.vendor.qspa=true \
    androidboot.console=0

BOARD_KERNEL_CMDLINE += \
    video=vfb:640x400,bpp=32,memsize=3072000 nosoftlockup pstore.compress=none \
    page_pinner=on printk.devkmsg=on mem.enable_mglru=1

BOARD_DTBOIMG_PARTITION_SIZE := 16777216

# Ship dtbo as a build output so AVB covers it. Stock's vbmeta has a `dtbo` hash
# descriptor; ours did NOT, because we left the stock dtbo partition alone and
# never produced a dtbo.img. The device's first-stage fstab has
#   /dev/block/by-name/dtbo /dtbo emmc defaults slotselect,avb=vbmeta,first_stage_mount
# and that entry is processed BEFORE the /metadata entry -- the same shape as the
# vendor_dlkm/system_dlkm descriptor gap.
#
# The image is stock's own dtbo (11 overlays, magic d7b7ab1e, 4,358,387 bytes)
# with Motorola's AVB footer stripped, so our build appends OUR footer and adds
# a matching descriptor to our vbmeta. We build no kernel, so the overlays
# themselves must stay Motorola's.
#
# Still missing vs stock: a `pvmfw` descriptor. pvmfw is not in the fstab, so it
# is not part of first-stage mount; revisit only if this does not help.
BOARD_PREBUILT_DTBOIMAGE := $(COMMON_PATH)/prebuilt/dtbo/dtbo.img

# arcfox has a DEDICATED recovery partition (not recovery-as-boot; confirmed by
# the TWRP tree, which drops BOARD_USES_RECOVERY_AS_BOOT). Size from the
# shipping firmware's recovery.img.
#
# This also unblocks the OTA zip. build/make/core/Makefile only assigns
# `recovery_fstab` inside the recovery-image section, and build_ota_package is
# set false when recovery_fstab is empty. The resulting failure names the ZIP,
# not the recovery image:
#   ln: cannot create hard link ... lineage-23.2-...-arcfox.zip: No such file
# because INTERNAL_OTA_PACKAGE_TARGET expands to nothing.
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 134217728

# arcfox's recovery partition holds a RAMDISK ONLY — the kernel comes from boot.
# Verified by unpacking the shipping recovery.img:
#   stock : kernel_size 0,        ramdisk 19243852, os_version None
#   ours  : kernel_size 35564032, ramdisk 16030315, os_version 16.0.0
# Handing the bootloader a recovery image with an embedded kernel produced
# "No valid operating system found" on two flash attempts. The working arcfox
# TWRP tree (bidbuddyai/device_motorola_arcfox) sets exactly these, with the
# commit message "match GKI stock recovery header".
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true

# Zero the version fields to match stock's header. Uses the RECOVERY-specific
# variable so boot.img keeps its own os_version (stock boot.img reports 14).
BOARD_RECOVERY_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION) --os_version 0 --os_patch_level 0

BOARD_AVB_RECOVERY_ADD_HASH_FOOTER_ARGS += --partition_size 134217728

# --- Partitions -------------------------------------------------------------
# A/B with dynamic partitions. Confirmed on-device: ro.boot.slot_suffix=_a,
# ro.build.ab_update=true, ro.boot.dynamic_partitions=true.
# PRODUCT_USE_DYNAMIC_PARTITIONS lives in common.mk: it is a PRODUCT variable
# and is readonly here ("cannot assign to readonly variable").

AB_OTA_UPDATER := true
BOARD_USES_METADATA_PARTITION := true

# Partition list from lpunpack on the real super.img for this build.
BOARD_SUPER_PARTITION_GROUPS := motorola_dynamic_partitions
# vendor_dlkm and system_dlkm are deliberately EXCLUDED. We do not build kernel
# modules: the 287 vendor_dlkm + 60 system_dlkm modules already on the handset
# were built against kernel 6.1.145-android14-11, which is exactly the prebuilt
# Image this ROM ships. Building them here fails with
#   build_image.py ... KeyError: 'partition_size'
# because nothing sizes an empty dynamic partition. Leaving them out means the
# stock ones are kept, which is what we want.
BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    vendor \
    vendor_dlkm \
    system_dlkm

# Declared size of the merged super.img (simg2img expands a sparse image to its
# declared partition size). UNVERIFIED against the device: /sys/class/block is
# SELinux-denied to the shell user, so this could not be cross-checked. If a
# build overflows, read the real geometry from gpt.bin.
BOARD_SUPER_PARTITION_SIZE := 26616004608
# Group size must be STRICTLY LESS than BOARD_SUPER_PARTITION_SIZE / 2: this is
# an A/B device, so super holds BOTH slots. Sizing the group at the full super
# fails with
#   RuntimeError: sum of sizes of ['motorola_dynamic_partitions'] is greater
#   than or equal to BOARD_SUPER_PARTITION_SIZE / 2
# super/2 here is 13308002304. Actual content is ~1.56GB, so 13.0GB leaves
# enormous headroom while staying under the limit.
BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE := 13000000000

# ext4, not erofs. Stock uses erofs and our erofs images DO mount by hand from
# a TWRP shell on this exact kernel, so erofs is not obviously broken -- but
# first-stage init still fails while handling the logical partitions (proved by
# erasing metadata immediately before a boot and finding it still unformatted,
# `dd ... skip=1024 count=4` -> 00 00 00 00). Meanwhile the same
# boot/init_boot/vbmeta with STOCK's super boots fine, so the fault is in the
# content of our images.
#
# LineageOS/android_device_motorola_sm8475-common (zeekr) ships ext4
# (TARGET_USERIMAGES_USE_EXT4, BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4)
# and never sets these to erofs. The device's own fstab lists an ext4 line for
# every one of these partitions as an alternative to the erofs line, so ext4 is
# fully supported here. Switching matches the known-good reference and removes
# erofs as a variable.
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
# We now BUILD vendor_dlkm and system_dlkm instead of reusing stock's images.
# The old "build_image.py KeyError: 'partition_size'" was caused by declaring
# these without listing the partitions in
# BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST -- nothing sized them. Both
# are now in that list, so they get sized like the others.
#
# Why bother, given the modules are Motorola's either way: the device's
# first-stage fstab mounts BOTH with `avb=vbmeta`, but our vbmeta carried NO
# descriptors for them, because they were never build outputs. The partitions
# held stock images with Motorola's own AVB footers, signed with Motorola's key,
# while every other partition in super was ours. Building them makes the whole
# super internally consistent and covered by our vbmeta.
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm

# Motorola's own modules, lifted from the stock vendor_dlkm/system_dlkm images
# in the firmware dump. They are matched to the prebuilt GKI Image we ship
# (6.1.145-android14-11) because they came from the same firmware.
#
# Aside on ABI: the community arcfox kernel prebuilts
# (pachdomenic/android_device_motorola_arcfox-kernel, lineage-23.0) are
# 6.1.128-android14-11 -- a different sublevel but the SAME KMI generation
# (android14-11), so those modules would also be ABI-compatible. We use stock's
# anyway, since they match our Image exactly.
# BOARD_VENDOR_KERNEL_MODULES: now populated by kernel.mk from the source build
# Load lists live in the DEVICE TREE now (peridot pattern), not in prebuilt/:
# kernel.mk validates every named module exists in the build intermediates and
# hard-errors otherwise, so the list must describe what we actually build.
# ⚠️ THREE modules are deliberately absent vs stock's 287:
#   qca_cld3_qca6750.ko  - the other WLAN variant; arcfox uses kiwi_v2
#                          (CONFIG_MOT_CNSS_KIWI_V2), so this one never loads.
# WLAN NOTE: the whole qcom/opensource/wlan subtree is LineageOS's (Xiaomi's),
# not Motorola's -- Motorola's qcacld-3.0 does not build (16 documented
# attempts, HANDOFF 0.28) and its qcacld requires its own cnss2, which exports
# cnss_register_driver_async_data_cb that Motorola's platform lacks. Taking the
# subtree wholesale is the only coherent option; a hybrid fails at modpost.
# Motorola's copy is kept beside it as wlan.motorola-unbuildable/.
# The one Motorola patch that DOES matter is ported back on top:
# hdd_update_mac_config reading the per-unit factory MAC from the bootloader's
# wifimacaddr= cmdline arg (patches/wlan/qcacld-bootarg-mac.patch in the
# workspace). Without it the driver falls back to the board-data placeholder
# 00:03:7F:12:34:56 -- identical on every unit, so two arcfox phones on one L2
# segment would collide. An earlier revision of this comment claimed the loss
# was "MAC randomized per boot, rather than derived from the serial": both
# halves were wrong. Stock never derived it from the serial (that path is dead
# code with a 38:80:DF OUI that does not match this device), and the fallback
# is fixed, not random.
#   moto_swap.ko         - kernel-side hybridswap memcg fields were never
#                          published; stock parity impossible from source.
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(COMMON_PATH)/modules/modules.list.vendor_dlkm 2>/dev/null))
BOARD_VENDOR_KERNEL_MODULES_BLOCKLIST_FILE := $(COMMON_PATH)/modules/modules.blocklist.vendor_dlkm
# system_dlkm modules MUST be installed into a VERSIONED subdirectory.
#
# The loader is stock's own /vendor/bin/system_dlkm_modprobe.sh, run by the
# gki.modprobe service (init.qti.kernel.rc:38, `exec_start`, gated on
# ro.vendor.qti.load_dlkm.service="" -- which is our case). Its very first test
# is a glob over a version subdirectory:
#
#   SYSTEM_DLKM_DIR="/system_dlkm/lib/modules"
#   if [ ! -e ${dir}/*/modules.load ]; then continue; fi     <-- flat layout MISSES
#   ${MODPROBE} -b -s -d ${dir}/*/ -a ${first_module}
#
# AOSP installs BOARD_SYSTEM_KERNEL_MODULES FLAT (BOARD_KERNEL_MODULE_DIRS
# defaults to just `top`, build/make/core/Makefile:703), so the glob never
# matched, the loop hit `continue`, the script `exit 1`ed, and NONE of the 60
# modules loaded -- silently, with no error anywhere. Populating modules.load
# was necessary but NOT sufficient: verified on a flashed image where the file
# had all 60 entries and `lsmod` still showed only the 387 vendor_dlkm ones.
# That is what kept costing mobile data (tipc.ko -> AF_TIPC -> dsi_init ->
# SETUP_DATA_CALL); it was masked for weeks by hand-running insmod after boot.
#
# Naming the directory after the modules' own vermagic reproduces stock exactly
# (stock ships /system_dlkm/lib/modules/6.1.145-android14-11-geaa643a2c0ee-...).
# The script only globs `*`, so any single subdirectory would satisfy it, but
# matching stock keeps modprobe's own version handling honest.
#
# ⚠️ This file is now ALSO the kernel/module consistency contract: Android.mk in
# this directory asserts that TARGET_PREBUILT_KERNEL reports exactly this
# version and fails the build otherwise. An earlier revision of this comment
# said the mismatch (6.1.128 Image vs 6.1.145 modules) was harmless because the
# KMI generation matched and "they load fine". That was wrong and it cost WiFi,
# Bluetooth and mobile data: these modules are SIGNED, and the kernel refuses a
# module signed by another build that exports a protected symbol (EACCES, from
# the !mod->sig_ok gate in verify_exported_symbols). The "443 modules" reading
# that appeared to justify it was measured on the 6.1.128 module set, which a
# stale out/ image was still supplying at the time.
#
# The version lives in a text file beside the modules, NOT sniffed from a .ko
# here: soong runs $(shell) with a RESTRICTED PATH, so `strings` is unavailable
# and the extraction silently returned empty (the $(error) below caught it).
# `cat` is available -- it is how modules.load is already read. Regenerate the
# file whenever these blobs are re-extracted:
#   strings -a prebuilt/system_dlkm_modules/tipc.ko \
#     | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | head -1 \
#     > prebuilt/system_dlkm_modules/kernel_version
# SOURCE BUILD: no SYSTEM_DLKM_KVER machinery any more.
# All of the above (versioned install dir, the kernel_version text file, the
# unsuffixed BOARD_SYSTEM_KERNEL_MODULES depmod feed) existed to make PREBUILT
# system_dlkm .ko land in lib/modules/<kver>/ so stock's gki.modprobe glob
# (`${dir}/*/modules.load`) would find them. kernel.mk's modules_install does
# that natively from the source build -- it installs into
# lib/modules/$(cat include/config/kernel.release)/ -- and populates both
# BOARD_SYSTEM_KERNEL_MODULES and the depmod inputs itself, so the seven
# cfg80211->rfkill style dependency edges documented above are preserved
# without the manual plumbing. Keeping the old block would also hard-error at
# config time, since it read a file that no longer exists.
BOARD_SYSTEM_KERNEL_MODULES_LOAD := $(strip $(shell cat $(COMMON_PATH)/modules/modules.list.system_dlkm 2>/dev/null))

# --- Verified boot ----------------------------------------------------------
# Rollback index read from this build's vbmeta.img with avbtool:
#   Rollback Index: 26   (chain: vbmeta_system at location 2)
# Note Motorola-Pineapple's abandoned tree hardcodes 16, correct for the
# Sept 2025 firmware they worked against. Do not copy that value.
BOARD_AVB_ENABLE := true
BOARD_AVB_ROLLBACK_INDEX := 26
# BOARD_AVB_VBMETA_SYSTEM is what actually GENERATES vbmeta_system.img. Without
# it the two ROLLBACK_INDEX lines below are inert and no image is produced, so
# the device keeps STOCK's vbmeta_system -- which describes stock's
# system/system_ext/product hashtrees, not ours. Stock's first-stage fstab
# (vendor_boot -> first_stage_ramdisk/fstab.qcom) mounts all three with
# `avb=vbmeta_system`, so that mismatch fails first-stage mount silently, before
# console or adb exist. Symptom: hangs at the Motorola logo, burns an A/B retry.
#
# Values taken from LineageOS/android_device_motorola_sm8475-common (zeekr,
# Razr 40 Ultra) -- an officially supported Motorola foldable on the sibling
# platform. It is the reference implementation for this whole arrangement.
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := 26
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2
# Custom builds ship vbmeta with verity and verification disabled.
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

# --- Security patch ---------------------------------------------------------
# ro.vendor.build.security_patch on the shipping build. Note the boot image
# itself reports os_version 14 with fingerprint UUX3S4HV-W1-45-ST13.1: the GKI
# boot image was not rebuilt for Android 16, which is why uname still says
# android14-11. That is expected, not a packaging error.
BOOT_SECURITY_PATCH := 2026-07-01
VENDOR_SECURITY_PATCH := $(BOOT_SECURITY_PATCH)

# --- Vendor interface -------------------------------------------------------
# Vendor stays FROZEN at API 34 across the Android 16 upgrade. This is Android's
# vendor-freeze design, not a mistake to "fix". Motorola ships and tests an
# Android 16 system against this API-34 vendor image, which is precisely what
# makes LineageOS 23.x a validated pairing here.
BOARD_SHIPPING_API_LEVEL := 34
# Do NOT set BOARD_API_LEVEL here. build/make/core/board_config.mk:1035 rejects
# it ("must not be set manually"), and the resulting failure is masked: lunch's
# check_product swallows the message, falls back to roomservice, and reports
# "Cannot locate config makefile for product" instead. That error is a red
# herring; the product was found fine.

# --- VINTF ------------------------------------------------------------------
# check_vintf fails image assembly with
#   Fetch 'out/.../vendor/etc/vintf/manifest.xml': NAME_NOT_FOUND
# Stock ships no manifest.xml: it uses SKU-selected manifest_pineapple.xml /
# manifest_cliffs.xml chosen by ro.boot.product.vendor.sku. Use the pineapple
# (SM8635 platform) manifest as the device manifest.
#
# ⚠️ THIS FILE IS BUILD-TIME ONLY. The old note here claimed the SKU "reads
# empty"; it does not -- ro.boot.product.vendor.sku is "cliffs" on this device,
# so at runtime libvintf reads /vendor/etc/vintf/manifest_cliffs.xml and RETURNS
# without ever reading manifest.xml (VintfObject.cpp:359-384 is a priority
# chain, not a merge). Everything in DEVICE_MANIFEST_FILE is therefore inert on
# the device and only feeds check_vintf. Runtime declarations MUST go in a
# fragment under /vendor/etc/vintf/manifest/; see Android.bp.
DEVICE_MANIFEST_FILE := $(COMMON_PATH)/manifest.xml

# Framework matrix extension declaring the vendor HALs the stock image provides.
# Without it, check_vintf_compatible reports ~30 unrecognised vendor.qti.* /
# com.qualcomm.* / motorola.* interfaces and the build ends in "INCOMPATIBLE".
# Generated from that exact log; see the header in the file.
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := $(COMMON_PATH)/device_framework_matrix.xml

# --- Filesystem config (Android IDs) -----------------------------------------
# Qualcomm/Motorola vendor init scripts reference custom AIDs (vendor_qti_diag,
# vendor_thermal, vendor_rfs, ...). Without this, host_init_verifier fails at
# image assembly with:
#   "Unable to decode GID for 'vendor_qti_diag': getpwnam failed"
# Sourced from Motorola-Pineapple/android_device_motorola_sm8650-common, which
# imported it from the real Qualcomm vendor release
# (LA.VENDOR.14.3.0.r1-22400-lanai.QSSI15.0). Same SM8635/pineapple platform.
TARGET_FS_CONFIG_GEN := $(COMMON_PATH)/configs/config.fs

# --- Properties -------------------------------------------------------------
TARGET_SYSTEM_PROP += $(COMMON_PATH)/system.prop
TARGET_VENDOR_PROP += $(COMMON_PATH)/vendor.prop

# --- Wi-Fi --------------------------------------------------------------------
# Build wpa_supplicant FROM SOURCE. Motorola's blob cannot run on this build at
# all -- it is linked against their own /vendor/lib64/libcrypto.so, an older
# BoringSSL. Ours is close but not identical: of the eight bare-stack sk_* names
# the blob imports, our libcrypto exports seven and is missing exactly one,
# sk_dup, which upstream retired in favour of OPENSSL_sk_dup. One missing symbol
# is enough -- the loader resolves all or nothing:
#   CANNOT LINK EXECUTABLE "/vendor/bin/hw/wpa_supplicant":
#   cannot locate symbol "sk_dup"
# (The supplicant also imports EVP_PKEY_from_keystore, likewise unexported here.
# Do not read the old "exports only the OPENSSL_sk_* names" claim that used to
# sit in this comment -- it was measured properly on 2026-08-10 and is false.)
# The only way to satisfy it would be to ship Motorola's libcrypto.so as
# /vendor/lib64/libcrypto.so, which -- via extract_utils' prefer:true -- would
# swap the C crypto library out from under EVERY vendor process. Not acceptable
# for one binary, so the blob is dropped from proprietary-files.txt instead.
#
# Source-built supplicant is also what every other LineageOS Qualcomm target
# does: external/wpa_supplicant_8 + hardware/qcom-caf/wlan/qcwcn's
# lib_driver_cmd_qcwcn. It talks to the driver over nl80211, so it does NOT
# share a private C++ ABI with the Motorola Wi-Fi HAL blob we keep -- this is a
# clean interface, not the source/blob mixing that broke the display stack.
#
# Deliberately NOT setting WIFI_DRIVER_STATE_CTRL_PARAM: that would compile the
# /dev/wlan "ON" write into a source-built libwifi_hal. We keep Motorola's
# libwifi-hal.so blob (its only consumer is android.hardware.wifi-service) and
# the write works now that the driver probes -- see the WCNSS_qcom_cfg.ini note
# in proprietary-files.txt.
#
# Deliberately NOT setting BOARD_WLAN_DEVICE either, and this is not an omission:
#   * For the supplicant it buys nothing. wpa_supplicant_driver_cflags_default
#     selects on it, but the `qcwcn` branch and the `default` branch are the SAME
#     value, -DCONFIG_DRIVER_NL80211_QCA.
#   * For libwifi_hal it is fatal IN THIS TREE. Setting it makes
#     libwifi_hal_vendor_impl_defaults pull `defaults: ["libwifi-hal-qcom"]`, and
#     soong fails with
#       error: module "libwifi-hal": defaults: module libwifi-hal-qcom is not an
#       defaults module
#     Note WHY, because the obvious reading is wrong: a proper cc_defaults named
#     libwifi-hal-qcom does exist, in hardware/qcom-caf/wlan/Android.bp. It gets
#     shadowed by the cc_library of the same name in
#     hardware/qcom-caf/wlan/qcwcn/wifi_hal/Android.bp -- which is only visible
#     because WE import the qcwcn namespace (needed for lib_driver_cmd_qcwcn).
#     So this is a consequence of our own namespace import, not a defect in qcwcn.
#     Resolving it properly would mean importing the parent namespace instead and
#     checking nothing else collides; not worth it, because we do not want a
#     source libwifi_hal at all -- the Motorola blob is the one that works and it
#     overrides the source module via prefer:true.
#
# WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY is REQUIRED, not cosmetic. The
# source wpa_supplicant's init_rc is behind that soong config variable; without
# it the binary installs with NO init rc at all and nothing can ever start it --
# the same "HAL binary shipped with no .rc" failure this port has already hit
# ten times. It matters even more here because the blob's rc was removed with
# the blob.
BOARD_WPA_SUPPLICANT_DRIVER                   := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB              := lib_driver_cmd_qcwcn
WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true
WPA_SUPPLICANT_VERSION                        := VER_0_8_X

# hostapd, same story and the same fix. The blob at /vendor/bin/hw/hostapd
# imports sk_dup too, so it could never have exec'd on this build either -- which
# is why IHostapd/default has never been registered and SoftAP/Wi-Fi tethering
# has never worked.
#
# TWO independent blockers, each on its own sufficient, and it is worth knowing
# both because fixing only one would have looked like progress and changed
# nothing:
#   1. the binary was dead on arrival, exactly like the supplicant, and for the
#      identical reason (sk_dup);
#   2. android.hardware.wifi.hostapd was never VINTF-declared AT ALL. No
#      hostapd fragment was ever extracted, and neither manifest_cliffs.xml nor
#      manifest_pineapple.xml -- the SKU manifests libvintf actually reads --
#      mentions IHostapd. HostapdHal gates the whole AIDL path on
#      HostapdHalAidlImp.serviceDeclared(), i.e. ServiceManager.isDeclared(),
#      which reads the VINTF manifest; the `interface aidl ...` line in the init
#      rc does NOT satisfy it. So even a perfectly linkable blob was unreachable.
# Building from source fixes both at once, because the cc_binary brings its own
# vintf_fragment_modules (see below).
#
# BOARD_HOSTAPD_DRIVER is the ON SWITCH, not just a driver selector. Setting it
# is what makes board_config_wpa_supplicant.mk set soong's wpa_build_hostapd,
# and hostapd_cflags_default carries `enabled: select(... wpa_build_hostapd ...)`
# defaulting to FALSE. Without this line the hostapd modules are disabled and
# adding `hostapd` to PRODUCT_PACKAGES fails to find a module rather than
# silently building nothing. NL80211 is the only accepted value (anything else
# is a hard $(error) in that file).
#
# Unlike the supplicant, hostapd needs no rc/VINTF coaxing: its cc_binary carries
# init_rc unconditionally and declares its own vintf_fragment_modules, so
# IHostapd/default is declared at version 3 automatically. That is a REAL version
# change from the blob, which was built against hostapd-V1-ndk -- and it is the
# right direction: source-built means implementation and NDK backend are the same
# version by construction, so the V1-vs-V4 relink trap that crashed the Wi-Fi HAL
# cannot happen here.
#
# V3 against a target-level 8 device is fine, but the reason is not obvious:
# compatibility_matrix.8.xml asks for hostapd <version>1</version>, and libvintf
# matches with minorAtLeast() against a fake AIDL major, so 3 satisfies 1. Do not
# "fix" the fragment down to 1 -- and do re-run check_vintf after touching it.
#
# 11AX and 11BE are enabled to match stock: Motorola's own hostapd blob contains
# both the ieee80211ax and the ieee80211be config strings. Without 11AX the
# SoftAP tops out at 11n on 2.4 GHz (measured: wifiStandard=4) and at 11ac on
# 5/6 GHz -- 11ac does not exist on 2.4 GHz at all.
BOARD_HOSTAPD_DRIVER                          := NL80211
BOARD_HOSTAPD_PRIVATE_LIB                     := lib_driver_cmd_qcwcn
WIFI_FEATURE_HOSTAPD_11AX                     := true
WIFI_FEATURE_HOSTAPD_11BE                     := true

# --- Blobs ------------------------------------------------------------------
-include vendor/motorola/sm8635-common/BoardConfigVendor.mk

# --- SELinux vendor policy ---------------------------------------------------
# We shipped NO device sepolicy at all. Consequence, measured against stock:
#   vendor_sepolicy.cil      209,852 B (bare AOSP skeleton)  vs  1,380,804 B
#   vendor_file_contexts     209 lines                       vs  1,452 lines
# so essentially every one of the 68 restored vendor HAL binaries is labelled
# plain `vendor_file` with no domain transition. init/service.cpp:
#
#   if (rc == 0 && computed_context == mycon.get()) {
#       ...
#       if (security_getenforce() != 0) { return Error() << error; }   <-- FATAL
#       LOG(ERROR) << error;                                           <-- permissive: continues
#   }
#
# i.e. a missing domain transition is only fatal when ENFORCING. The old
# `androidboot.selinux=permissive` test therefore did NOT rule SELinux out --
# it masked exactly this, and it was run when vendor shipped 15 HALs, not 68.
# The permissive flag has since been removed, so the current build is enforcing
# and cannot start any of those services.
#
# Qualcomm's vendor policy is already in the tree. SEPolicy.mk keys off
# TARGET_BOARD_PLATFORM via hardware/qcom-caf/common/qcom_defs.mk
# (UM_6_1_FAMILY := pineapple volcano), so `pineapple` selects the sm8650
# flavour, which has a generic/vendor/pineapple directory.
#
# Bonus: sm8650/generic/vendor/*/genfs_contexts carries the
# /devices/platform/soc/a600000.ssusb labels that the recovery-USB dead end
# independently identified as missing -- one fix, two open problems.
-include device/qcom/sepolicy_vndr/SEPolicy.mk

# Motorola-specific labels go here, grown from actual denials/refusals.
BOARD_VENDOR_SEPOLICY_DIRS += $(COMMON_PATH)/sepolicy/vendor
