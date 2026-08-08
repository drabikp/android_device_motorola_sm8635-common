#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Motorola SM8635 (Snapdragon 8s Gen 3, "pineapple") common tree.

from extract_utils.fixups_blob import (
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.fixups_lib import (
    lib_fixups,
    lib_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)

namespace_imports = [
    'hardware/qcom-caf/sm8650',
    'hardware/qcom-caf/wlan',
    'vendor/qcom/opensource/commonsys/display',
    'vendor/qcom/opensource/commonsys-intf/display',
    'vendor/qcom/opensource/dataservices',
    'vendor/qcom/opensource/display',
]

lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
}

blob_fixups: blob_fixups_user_type = {
    # --- tinyxml2 ABI break: THIS ONE STOPPED THE BOOT ------------------------
    # LineageOS ships tinyxml2 11.0.0, where sizeof(XMLDocument) is 880. Every
    # Motorola vendor blob was compiled against 10.x, where it is 776, and
    # several stack-allocate an XMLDocument.
    #
    # Verified by disassembling the shipping blob:
    # snapdragoncolor::StcOrderParserImpl::ParseFile reserves the object at
    # sp+0x68 and memsets exactly 0x308 = 776 bytes, with its own callee-saved
    # x19..x28 immediately above it. The 11.0.0 constructor writes 880 -- 104
    # bytes past the reservation, landing precisely on those saved registers. So
    # ParseFile logs "Load XML file ... successful", returns with `this` (x20)
    # zeroed, and the caller null-derefs at StcOrderParserImpl::Init()+132. The
    # tombstone matches exactly: x20-x25 zeroed, x26 = 0xa.
    #
    # That is six frames under sdm::CoreImpl::CreateDisplay, so it kills the
    # display composer -- and the composer's .rc restarts surfaceflinger, whose
    # .rc restarts zygote. The entire framework went down every 5s, 52 times.
    #
    # The 10.x library is ALREADY in the image: Motorola ships their own private
    # copy as vendor/lib64/libtinyxml2_1.so (198 exported tinyxml2 symbols, 115 KB)
    # and 14 of their display libs -- libsdmextension, libsdm-color,
    # libqdcm-mode-parser ... -- already link it by that name. Only this handful
    # link the bare "libtinyxml2.so".
    #
    # On stock, /vendor/lib64/libtinyxml2.so does not exist as a regular file --
    # it is a SYMLINK to libtinyxml2_1.so, and extract_utils drops symlinks (the
    # same trap as media_profiles_vendor.xml). So these blobs resolved to the
    # 10.x copy on stock, and to the platform's 11.x libtinyxml2.vendor on ours.
    #
    # Do NOT "fix" this by shipping stock's system/lib64/libtinyxml2.so: stock is
    # Android 16 and that copy is ALSO 11.x (230 symbols, same count as ours).
    # It was tried and would have been a no-op. Repointing DT_NEEDED at
    # libtinyxml2_1.so is the fix, and needs no new file.
    (
        'vendor/bin/qvrdatauploader',
        'vendor/bin/hw/motorola.hardware.sensorext-service',
        'vendor/bin/hw/vendor.qti.hardware.display.composer-service',
        'vendor/lib64/libaodoptfeature.so',
        'vendor/lib64/libapengine.so',
        'vendor/lib64/libdpps.so',
        'vendor/lib64/libeffectsconfig.so',
        'vendor/lib64/libgamepoweroptfeature.so',
        'vendor/lib64/liblearningmodule.so',
        'vendor/lib64/liboffscreenpoweroptfeature.so',
        'vendor/lib64/libpowercore.so',
        'vendor/lib64/libpsmoptfeature.so',
        'vendor/lib64/libsnapdragoncolor-manager.so',
        'vendor/lib64/libstandbyfeature.so',
        'vendor/lib64/libvideooptfeature.so',
    ): blob_fixup()
        .replace_needed('libtinyxml2.so', 'libtinyxml2_1.so'),
    # --- VINTF versions must match the .replace_needed bumps below ------------
    # Every HAL whose AIDL version we rewrite in its ELF must ALSO have its vintf
    # manifest updated, or the HAL registers as (say) V4 while the framework
    # looks up V3 and blocks forever. Observed exactly that: keystore2 never
    # started because keymint advertised <version>3</version> while the binary
    # linked keymint-V4-ndk, and vold then waited on keystore2 indefinitely.
    # The two keymint manifest rewrites that used to be here are REMOVED, together
    # with the ELF .replace_needed they existed to match (see the long note further
    # down). The blobs link keymint-V3 again, so the manifest must say 3 again --
    # and it must, because the same blanket regex also bumped
    # IRemotelyProvisionedComponent to 4, which the 202504 compatibility matrix
    # does not allow (it accepts rkp 1-3).
    'vendor/etc/vintf/manifest/android.hardware.health-service.qti.xml': blob_fixup()
        .regex_replace('<version>2</version>', '<version>4</version>'),
    # (the sensors-multihal.xml version rewrite is gone with it -- that file cannot
    # be shipped as a blob at all, since AOSP's hardware/interfaces/sensors/aidl/multihal
    # already defines it; the HAL is declared in sm8635-common/manifest.xml instead)
    'vendor/etc/vintf/manifest/android.hardware.wifi.supplicant.xml': blob_fixup()
        .regex_replace('<version>2</version>', '<version>5</version>'),
    'vendor/etc/vintf/manifest/bluetooth_audio.xml': blob_fixup()
        .regex_replace('<version>3</version>', '<version>5</version>'),
    'vendor/etc/vintf/manifest/face-default_3.xml': blob_fixup()
        .regex_replace('<version>3</version>', '<version>4</version>'),

    # Motorola's vendor is frozen at vendor API level 34, so these HALs link
    # OLDER AIDL interface versions than the rest of the dependency graph settles
    # on, and soong refuses a module that depends on two versions of one
    # aidl_interface. The platform ships every one of these versions (health
    # V1-V4, sensors V1-V3, supplicant V1-V4), so nothing is missing -- the blob
    # just needs repointing at the version everything else uses.
    #
    # These MUST live in the common tree's extract-files.py: the blobs are listed
    # in sm8635-common/proprietary-files.txt, and fixups only apply to the module
    # that owns the list. Putting them in arcfox/extract-files.py silently does
    # nothing (verified with readelf on the staged blob).
    # Sensors: the blob links sensors-V2, but AOSP's own
    # android.hardware.sensors-service.multihal module is in this build's graph and
    # pulls V3, so requesting a V2 vendor variant fails with "depends on multiple
    # versions of the same aidl_interface". Repointed to V3 and DECLARED as v3 in
    # manifest.xml so the ELF and the VINTF entry agree -- the pairing that matters.
    # (Ideally we would ship V2 and declare v2, as done for keymint; that needs the
    # AOSP multihal module out of the graph, or a renamed prebuilt + DT_NEEDED
    # repoint as done for tinyxml2. Revisit.)
    'vendor/bin/hw/android.hardware.sensors-service.multihal': blob_fixup()
        .replace_needed(
            'android.hardware.sensors-V2-ndk.so',
            'android.hardware.sensors-V3-ndk.so'
    ),
    'vendor/bin/hw/android.hardware.health-service.qti': blob_fixup()
        .replace_needed(
            'android.hardware.health-V2-ndk.so',
            'android.hardware.health-V4-ndk.so'
    ),
    'vendor/bin/hw/wpa_supplicant': blob_fixup()
        .replace_needed(
            'android.hardware.wifi.supplicant-V2-ndk.so',
            'android.hardware.wifi.supplicant-V5-ndk.so'
        )
        # Drop the keystore engine libs entirely. They exist so supplicant can use
        # keystore-backed EAP certificates (enterprise Wi-Fi); they drag
        # keymint-V1 into the graph against the platform's V4 and no version
        # rewrite clears it. Normal WPA2/WPA3-PSK does not touch them.
        # Cost: enterprise EAP-TLS with keystore-held certs will not work.
        .remove_needed('libkeystore-engine-wifi-hidl.so')
        .remove_needed('libkeystore-wifi-hidl.so'),
    # Bluetooth audio HAL: links bluetooth.audio-V3 while the graph resolves to
    # V5. Platform ships V1-V5.
    # Fingerprint FPC: links biometrics.common-V3 / fingerprint-V3 while the
    # graph resolves to V4 (platform ships 1-4 of both). Same treatment as
    # sensors/health/supplicant -- repoint at V4 instead of parking the HAL.
    'vendor/bin/hw/android.hardware.biometrics.fingerprint-service.fpc': blob_fixup()
        .replace_needed(
            'android.hardware.biometrics.common-V3-ndk.so',
            'android.hardware.biometrics.common-V4-ndk.so'
        )
        .replace_needed(
            'android.hardware.biometrics.fingerprint-V3-ndk.so',
            'android.hardware.biometrics.fingerprint-V4-ndk.so'
    ),
    # Face unlock: same biometrics V3 -> V4 bump as fingerprint.
    'vendor/bin/hw/android.hardware.biometrics.face@1.0-service.face': blob_fixup()
        .replace_needed(
            'android.hardware.biometrics.common-V3-ndk.so',
            'android.hardware.biometrics.common-V4-ndk.so'
        )
        .replace_needed(
            'android.hardware.biometrics.face-V3-ndk.so',
            'android.hardware.biometrics.face-V4-ndk.so'
    ),
    # Wi-Fi HAL: links wifi-V1 while the graph resolves to V4. This was parked
    # earlier; the widened sweep re-added it, and the fixup route works.
    'vendor/bin/hw/android.hardware.wifi-service': blob_fixup()
        .replace_needed(
            'android.hardware.wifi-V1-ndk.so',
            'android.hardware.wifi-V4-ndk.so'
    ),
    # NOTE: the keymint V3->V4 .replace_needed that used to live here has been
    # REMOVED. Do not put it back.
    #
    # It rewrote the ELF DT_NEEDED of libqtikeymint.so, libtpa.so,
    # libjc_keymint-thales.so and the two keymint service binaries from
    # keymint-V3-ndk.so to V4, because we shipped V4 and not V3. But an AIDL
    # NDK backend is not ABI-compatible across a version bump -- these blobs are
    # COMPILED against V3, and stock accommodates that by shipping
    # keymint-V2-ndk.so AND keymint-V3-ndk.so in /vendor/lib64 (both are in
    # stock's vendor image and were missing from ours). Relinking a V3 blob
    # against V4 makes it load, and then wedge: keymint-qti starts, emits three
    # TimedRetryForwarder_release lines at 2.6s and never says anything again,
    # never reaches AServiceManager_addService, so keystore2 cannot build the
    # TEE security level and vold blocks forever in "Generating wrapped storage
    # key". No crash, no SELinux denial -- exactly what an ABI mismatch across
    # a binder proxy looks like.
    #
    # The fix is to ship what the blobs were built against: common.mk now
    # declares android.hardware.security.keymint-V2-ndk.vendor and -V3-ndk.vendor.
    # The 202504 compatibility matrix accepts IKeyMintDevice 1-4, so V3 is a
    # legal declaration -- and IRemotelyProvisionedComponent only accepts 1-3,
    # which the blanket manifest rewrite (also removed, above) had pushed out of
    # range by bumping it to 4.
    # The identity-credential pair's keymint-V2 -> V4 rewrite is also REMOVED.
    # Same defect as the keymint chain above, and now free to fix: common.mk
    # ships keymint-V2-ndk.vendor, which is what these two were compiled
    # against and what stock ships in /vendor/lib64.
    # libkeystore-engine-wifi-hidl is what actually dragged keymint-V1 into
    # wpa_supplicant's closure (via keystore2-V1), long after the binary's own
    # NEEDED entries were clean. Transitive deps matter: fix the library, not
    # just the executable.
    'vendor/lib64/libkeystore-engine-wifi-hidl.so': blob_fixup()
        .replace_needed(
            'android.system.keystore2-V1-ndk.so',
            'android.system.keystore2-V5-ndk.so'
    ),
    'vendor/lib64/hw/audio.bluetooth.default.so': blob_fixup()
        .replace_needed(
            'android.hardware.bluetooth.audio-V3-ndk.so',
            'android.hardware.bluetooth.audio-V5-ndk.so'
    ),
    # Every common-tree blob that links graphics.allocator V1 while the graph
    # resolves to V2. Found by readelf-ing every entry in proprietary-files.txt --
    # 53 of them, almost all the camera stack. Rescan after any widening
    # of the blob list; discovering these one failed build at a time is hopeless.
    (
        'vendor/bin/aecxsimulator',
        'vendor/bin/hw/vendor.qti.hardware.display.allocator-service',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kgn8_cli_eeprom.so',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kgn8_eeprom.so',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kjn1_cli_eeprom.so',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kjn1_eeprom.so',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kjn5_cli_eeprom.so',
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p128f_s5kjn5_eeprom.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kgn8.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kgn8_cli.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kjn1.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kjn1_cli.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kjn5.so',
        'vendor/lib64/camera/com.qti.sensor.mot_s5kjn5_cli.so',
        'vendor/lib64/com.qti.camx.chiiqutils.so',
        'vendor/lib64/com.qti.feature2.afbrckt.so',
        'vendor/lib64/com.qti.feature2.anchorsync.so',
        'vendor/lib64/com.qti.feature2.arcoffline.so',
        'vendor/lib64/com.qti.feature2.arcrawpro.so',
        'vendor/lib64/com.qti.feature2.demux.so',
        'vendor/lib64/com.qti.feature2.fusion.so',
        'vendor/lib64/com.qti.feature2.generic.so',
        'vendor/lib64/com.qti.feature2.gs.sm8650.so',
        'vendor/lib64/com.qti.feature2.hdr.so',
        'vendor/lib64/com.qti.feature2.mcreprocrt.so',
        'vendor/lib64/com.qti.feature2.memcpy.so',
        'vendor/lib64/com.qti.feature2.metadataserializer.so',
        'vendor/lib64/com.qti.feature2.mfsr.so',
        'vendor/lib64/com.qti.feature2.mux.so',
        'vendor/lib64/com.qti.feature2.rawhdr.so',
        'vendor/lib64/com.qti.feature2.realtimeserializer.so',
        'vendor/lib64/com.qti.feature2.rt.so',
        'vendor/lib64/com.qti.feature2.rtmcx.so',
        'vendor/lib64/com.qti.feature2.serializer.so',
        'vendor/lib64/com.qti.feature2.swmf.so',
        'vendor/lib64/com.qti.qseeutils.so',
        'vendor/lib64/com.qualcomm.mcx.nonlinearmapper.so',
        'vendor/lib64/hw/camera.qcom.sm8650.so',
        'vendor/lib64/hw/camera.qcom.so',
        'vendor/lib64/hw/com.qti.chi.offline.so',
        'vendor/lib64/hw/com.qti.chi.override.so',
        'vendor/lib64/libarccamerapostproc_aidl.so',
        'vendor/lib64/libcamxhwnodecontext.so',
        'vendor/lib64/libcamximageformatutils.so',
        'vendor/lib64/libcamxncsdatafactory.so',
        'vendor/lib64/libchifeature2.so',
        'vendor/lib64/libcommonchiutils.so',
        'vendor/lib64/libisphwsetting.so',
        'vendor/lib64/libmctfengine_stub.so',
        'vendor/lib64/libmmcamera_cac.so',
        'vendor/lib64/vendor.qti.hardware.camera.aon-service-impl.so',
        'vendor/lib64/vendor.qti.hardware.camera.offlinecamera-service-impl.so',
        'vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so',
    ): blob_fixup()
        .replace_needed(
            'android.hardware.graphics.allocator-V1-ndk.so',
            'android.hardware.graphics.allocator-V2-ndk.so'
    ),
    # Display composer: links graphics.composer3-V2 while the graph resolves to
    # V4. Platform ships V1-V4. This one matters -- without the composer there is
    # no display.
    # The composer3 V2->V3 rewrite is REMOVED: proprietary-files.txt now ships
    # android.hardware.graphics.composer3-V2-ndk.so, which is what the stock
    # composer was built against. Same reasoning as the keymint V2/V3 libs --
    # ship the version the blob wants instead of relinking it to another ABI.
}  # fmt: skip

module = ExtractUtilsModule(
    'sm8635-common',
    'motorola',
    blob_fixups=blob_fixups,
    lib_fixups=lib_fixups,
    namespace_imports=namespace_imports,
)

if __name__ == '__main__':
    utils = ExtractUtils.device(module)
    utils.run()
