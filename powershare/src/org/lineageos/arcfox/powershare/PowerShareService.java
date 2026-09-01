/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.powershare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.drawable.Icon;
import android.os.BatteryManager;
import android.os.IBinder;
import android.os.SystemProperties;
import android.widget.Toast;

/**
 * Runs only while transmitting is armed. Two jobs, both of which the vendor HAL
 * would otherwise have covered and which nothing else on this ROM does:
 *
 * <ol>
 *   <li>Makes the state visible. A phone that is silently giving its battery
 *       away is a footgun; an ongoing notification is the cheapest honest fix,
 *       and it carries a one-tap "Turn off".</li>
 *   <li>Watches the battery, because ACTION_BATTERY_CHANGED is not delivered to
 *       manifest-declared receivers -- it has to be registered from a running
 *       component. Disarms below {@link PowerShare#AUTO_OFF_BATTERY_PERCENT},
 *       and disarms if this phone starts RECEIVING wireless power (it cannot do
 *       both).</li>
 * </ol>
 */
public class PowerShareService extends Service {

    private static final String CHANNEL_ID = "power_share";
    private static final int NOTIFICATION_ID = 1;

    private final BroadcastReceiver mBatteryReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (!PowerShare.isRequestedOn()) {
                stopSelf();
                return;
            }

            int plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
            if ((plugged & BatteryManager.BATTERY_PLUGGED_WIRELESS) != 0) {
                autoOff(R.string.toast_auto_off_wireless);
            } else if (PowerShare.percent(intent)
                    < PowerShare.AUTO_OFF_BATTERY_PERCENT) {
                autoOff(R.string.toast_auto_off_low);
            }
        }
    };

    private final BroadcastReceiver mStopReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            PowerShare.set(PowerShareService.this, false);
        }
    };

    private boolean mRegistered;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(NOTIFICATION_ID, buildNotification());

        if (!mRegistered) {
            registerReceiver(mBatteryReceiver,
                    new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            registerReceiver(mStopReceiver,
                    new IntentFilter(PowerShare.ACTION_STOP),
                    Context.RECEIVER_NOT_EXPORTED);
            mRegistered = true;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (mRegistered) {
            unregisterReceiver(mBatteryReceiver);
            unregisterReceiver(mStopReceiver);
            mRegistered = false;
        }
        // Never leave the node armed behind a dead watchdog.
        SystemProperties.set(PowerShare.PROPERTY, "0");
        sendBroadcast(new Intent(PowerShare.ACTION_STATE_CHANGED)
                .setPackage(getPackageName()));
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void autoOff(int toast) {
        Toast.makeText(this, toast, Toast.LENGTH_LONG).show();
        PowerShare.set(this, false);
    }

    private Notification buildNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                getString(R.string.notif_channel),
                NotificationManager.IMPORTANCE_LOW);
        nm.createNotificationChannel(channel);

        PendingIntent stop = PendingIntent.getBroadcast(this, 0,
                new Intent(PowerShare.ACTION_STOP).setPackage(getPackageName()),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, PowerShareActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_powershare)
                .setContentTitle(getString(R.string.notif_title))
                .setContentText(getString(R.string.notif_text,
                        PowerShare.AUTO_OFF_BATTERY_PERCENT))
                .setContentIntent(open)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(this, R.drawable.ic_powershare),
                        getString(R.string.notif_action_stop), stop).build())
                .build();
    }
}
