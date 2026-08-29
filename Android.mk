#
# SPDX-License-Identifier: Apache-2.0
#
# Installs the shipping GKI kernel, and refuses to build if it does not match
# the system_dlkm modules.
#
# WHY THIS FILE EXISTS
# --------------------
# AOSP defines INSTALLED_KERNEL_TARGET as a bare PATH and never supplies a rule
# to produce it (build/make/core/Makefile:1014) -- producing it is the kernel
# build's job. We set TARGET_NO_KERNEL_OVERRIDE := true, which disables all of
# vendor/lineage/build/tasks/kernel.mk (gated at kernel.mk:106), including the
# NEEDS_KERNEL_COPY path that would have installed TARGET_PREBUILT_KERNEL.
#
# The result was a silent, ten-day-long defect: nothing produced
# $(PRODUCT_OUT)/kernel, so make treated whatever file happened to be there as
# up to date. A hand-placed 6.1.128 GKI binary from 07 Aug (byte-identical to
# ~/android/kernel-src/arcfox-kernel-prebuilt/kernel, which no rule and no
# makefile in this tree references) shadowed prebuilt/Image and went into every
# boot.img we ever flashed. TARGET_PREBUILT_KERNEL was dead config.
#
# It stayed invisible because the stale out/ system_dlkm image happened to hold
# the MATCHING 6.1.128 modules, so the pair was consistent by accident. Commit
# 996f2e4 changed the system_dlkm output path, which forced that image to
# regenerate against the current 6.1.145 prebuilts -- and the accident ended.
# Loading then failed with EACCES on 12 modules ("exports protected symbol"),
# which cost WiFi (cfg80211 needs rfkill), Bluetooth (btpower, bt_fm_slim) and
# mobile data (tipc -> AF_TIPC -> dsi_init -> OEM_DCFAILCAUSE_4).
#
# ⚠️ CORRECTED 2026-08-18 -- the original text here overstated the constraint.
# It is NOT all 347 modules. The gate has TWO conditions and vendor modules fail
# only the first:
#   * the 60 system_dlkm .ko are GOOGLE'S GKI modules, SIGNED with a per-build
#     key, and are bound 1:1 to the exact GKI build. These are what fail EACCES.
#   * the 287 vendor_dlkm .ko are UNSIGNED -- AOSP states plainly that "module
#     signing is not supported for GKI vendor modules" -- and export no
#     protected symbols, so they load across GKI builds within one KMI
#     generation (android14-11 here). Verified locally: strings on cfg80211.ko,
#     qca_cld3_kiwi_v2.ko, msm_kgsl.ko, btpower.ko shows no signature trailer,
#     while tipc.ko/rfkill.ko/libarc4.ko are signed.
# Also: the kernel is GOOGLE'S certified GKI, not a Motorola build.
#   ab14763719 = android14-6.1-2025-09_r28,  ab13748990 = android14-6.1-2025-03_r12.
# CONSEQUENCE: a newer certified GKI CAN be adopted for CVE fixes -- swap
# boot.img AND its matching system_dlkm together, leave vendor_dlkm alone.
#
# The mechanism, stated exactly, because the obvious reading is wrong.
# It is NOT a version check. kernel/module/main.c:1283 (verify_exported_symbols):
#
#     if (!mod->sig_ok && gki_is_module_protected_export(...)) {
#             pr_err("%s: exports protected symbol %s\n", ...);
#             return -EACCES;
#     }
#
# The gate is mod->sig_ok -- whether the module's appended signature verifies
# against the key built into the running kernel. CONFIG_MODULE_SIG_PROTECT=y and
# there is no sig_enforce parameter to turn it off. So a SIGNED module set is
# bound to the kernel it was signed with, and mixing GKI builds is fatal for
# those modules regardless of how close the version numbers look. Proven by A/B
# on the handset: 6.1.128 tipc.ko insmods rc=0, 6.1.145 tipc.ko gives EACCES,
# same kernel, same second. (tipc is system_dlkm, hence signed. An unsigned
# vendor_dlkm module in the same experiment would have loaded either way.)
#
# Hence the assertion below. It guards the system_dlkm half specifically: that
# is the half that must come from the same GKI build as the kernel.

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),arcfox)

# The version the system_dlkm modules were built and signed for. Same file
# 996f2e4 uses to name the versioned module directory, so the kernel and the
# modules are checked against a single source of truth.
SM8635_KVER_FILE := $(LOCAL_PATH)/prebuilt/system_dlkm_modules/kernel_version

# Install prebuilt/Image as the kernel, and assert it matches.
#
# The version is read here in a RECIPE, not in a $(shell) at parse time: soong
# runs $(shell) with a restricted PATH where `strings` does not exist, and an
# earlier attempt to sniff vermagic that way silently expanded to empty (see the
# note on 996f2e4). A recipe runs under a normal shell. `grep -a` reads the
# binary without needing `strings` at all.
# NOTE: the target is spelled out rather than written as $(INSTALLED_KERNEL_TARGET).
# Android.mk files are included by main.mk BEFORE build/make/core/Makefile, which
# is where INSTALLED_KERNEL_TARGET is defined, so that variable is still empty
# here -- using it yields a rule with no target, which make accepts silently and
# ninja then reports as "missing and no known rule to make it".
# Guard rule below is only meaningful for a PREBUILT kernel; with the source
# build (kernel.mk) TARGET_PREBUILT_KERNEL is unset and kernel.mk owns
# $(PRODUCT_OUT)/kernel.
ifneq ($(TARGET_PREBUILT_KERNEL),)
$(PRODUCT_OUT)/kernel: $(TARGET_PREBUILT_KERNEL) $(SM8635_KVER_FILE)
	@echo "Kernel: $@ <- $(TARGET_PREBUILT_KERNEL)"
	@have=`grep -a -o -m1 'Linux version [^ ]*' $(TARGET_PREBUILT_KERNEL) | cut -d' ' -f3`; \
	 want=`cat $(SM8635_KVER_FILE)`; \
	 if [ -z "$$have" ]; then \
	   echo "*** cannot read a kernel version out of $(TARGET_PREBUILT_KERNEL)" >&2; \
	   exit 1; \
	 fi; \
	 if [ "$$have" != "$$want" ]; then \
	   echo "***"                                                               >&2; \
	   echo "*** KERNEL / system_dlkm MISMATCH -- refusing to build."           >&2; \
	   echo "***   kernel      : $$have"                                        >&2; \
	   echo "***                 ($(TARGET_PREBUILT_KERNEL))"                   >&2; \
	   echo "***   system_dlkm : $$want"                                        >&2; \
	   echo "***                 ($(SM8635_KVER_FILE))"                         >&2; \
	   echo "***"                                                               >&2; \
	   echo "*** system_dlkm modules are SIGNED for their own GKI build.       ">&2; \
	   echo "*** on any other kernel fails with EACCES on every module that"    >&2; \
	   echo "*** exports a protected symbol -- rfkill, libarc4, mii, tipc and 8">&2; \
	   echo "*** others -- which silently costs WiFi, Bluetooth and mobile data.">&2; \
	   echo "*** Ship the kernel and system_dlkm from ONE GKI build.            ">&2; \
	   echo "***"                                                               >&2; \
	   exit 1; \
	 fi
	$(copy-file-to-target)

endif
endif
