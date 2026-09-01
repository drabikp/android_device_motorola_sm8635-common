/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.powershare;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.SystemProperties;

/**
 * The whole contract with the platform, in one place.
 *
 * <p>Setting {@link #PROPERTY} makes init write /sys/class/power_supply/
 * wireless/device/tx_mode -- see device/motorola/sm8635-common/init/
 * init.arcfox-powershare.rc for why it goes through init and not through the
 * vendor HAL, and for the disassembly that establishes that the single write is
 * all stock's HAL does to enable transmitting.
 *
 * <p>IMPORTANT, and the one honest limitation of this implementation: the
 * property is the REQUESTED state. This app cannot read tx_mode back --
 * system_app has no SELinux access to sysfs (there is no `allow system_app
 * sysfs:file read` in AOSP), so there is no way to confirm from here that the
 * ADSP charger firmware accepted the request. Do not present the toggle
 * position as a measurement of the hardware.
 */
public final class PowerShare {

    private PowerShare() { }

    /**
     * Must be labelled u:object_r:exported_system_prop:s0 in
     * device/motorola/sm8635-common/sepolicy/system_ext/private/
     * property_contexts. That single line is the whole sepolicy cost of this
     * feature: exported_system_prop is already settable by system_app
     * (private/system_app.te) and already readable by every domain including
     * vendor_init (private/domain.te), which is what lets a /vendor rc file
     * key an action off it -- see init.arcfox-powershare.rc for why a plain
     * sys.* or a vendor.* name cannot work.
     *
     * <p>Deliberately not persist.*: transmitting must not silently survive a
     * reboot.
     */
    public static final String PROPERTY = "sys.arcfox.powershare";

    /** Below this, refuse to arm and disarm if already armed. */
    public static final int MIN_BATTERY_PERCENT = 20;

    /** Once armed, drop out at this level. */
    public static final int AUTO_OFF_BATTERY_PERCENT = 15;

    public static final String ACTION_STOP =
            "org.lineageos.arcfox.powershare.action.STOP";

    /** Sent whenever the requested state changes, so the tile can resync. */
    public static final String ACTION_STATE_CHANGED =
            "org.lineageos.arcfox.powershare.action.STATE_CHANGED";

    /** Why an attempt to arm was refused, or {@code null} if it was accepted. */
    public enum Blocker { BATTERY_LOW, RECEIVING_WIRELESS }

    public static boolean isRequestedOn() {
        return SystemProperties.getBoolean(PROPERTY, false);
    }

    /**
     * Arms or disarms transmitting. Returns the blocker if the request was
     * refused; {@code null} on success. Disarming is never refused.
     */
    public static Blocker set(Context context, boolean on) {
        if (on) {
            Blocker blocker = blocker(context);
            if (blocker != null) {
                return blocker;
            }
        }

        SystemProperties.set(PROPERTY, on ? "1" : "0");

        Intent service = new Intent(context, PowerShareService.class);
        if (on) {
            context.startForegroundService(service);
        } else {
            context.stopService(service);
        }

        context.sendBroadcast(new Intent(ACTION_STATE_CHANGED)
                .setPackage(context.getPackageName()));
        return null;
    }

    /**
     * Preconditions, checked against the framework only -- everything here is
     * ordinary BatteryManager state, which is why none of it needs the HAL.
     * These mirror three of the unavailability reasons stock's
     * WirelessPowerShareService reports (BATTERY_LOW,
     * WIRELESS_POWER_RECEIVING); the temperature and power-saver reasons are
     * left to the charger firmware.
     */
    public static Blocker blocker(Context context) {
        Intent battery = context.registerReceiver(null,
                new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (battery == null) {
            return null;
        }
        return blocker(battery);
    }

    public static Blocker blocker(Intent battery) {
        int plugged = battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        if ((plugged & BatteryManager.BATTERY_PLUGGED_WIRELESS) != 0) {
            return Blocker.RECEIVING_WIRELESS;
        }
        if (percent(battery) < MIN_BATTERY_PERCENT) {
            return Blocker.BATTERY_LOW;
        }
        return null;
    }

    public static int percent(Intent battery) {
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        if (level < 0 || scale <= 0) {
            return 100;
        }
        return Math.round(level * 100f / scale);
    }

    public static int messageFor(Blocker blocker) {
        switch (blocker) {
            case RECEIVING_WIRELESS:
                return R.string.err_receiving;
            case BATTERY_LOW:
            default:
                return R.string.err_battery_low;
        }
    }
}
