/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.powershare;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/**
 * The target of the injected Settings > Battery entry, and of the ongoing
 * notification. Built in code on purpose: no SettingsLib or AndroidX dependency,
 * so this app cannot be broken by an unrelated library bump.
 */
public class PowerShareActivity extends Activity {

    private Switch mSwitch;
    private TextView mStatus;

    private final BroadcastReceiver mStateReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            sync();
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setTitle(R.string.app_name);

        int pad = dp(24);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        mSwitch = new Switch(this);
        mSwitch.setText(R.string.app_name);
        mSwitch.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        mSwitch.setGravity(Gravity.CENTER_VERTICAL);
        mSwitch.setPadding(0, 0, 0, dp(16));
        mSwitch.setOnClickListener(v -> onToggled(mSwitch.isChecked()));
        root.addView(mSwitch, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView explain = new TextView(this);
        explain.setText(R.string.explain);
        explain.setPadding(0, 0, 0, dp(16));
        root.addView(explain);

        mStatus = new TextView(this);
        root.addView(mStatus);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        registerReceiver(mStateReceiver,
                new IntentFilter(PowerShare.ACTION_STATE_CHANGED),
                Context.RECEIVER_NOT_EXPORTED);
        sync();
    }

    @Override
    protected void onPause() {
        unregisterReceiver(mStateReceiver);
        super.onPause();
    }

    private void onToggled(boolean checked) {
        PowerShare.Blocker blocker = PowerShare.set(this, checked);
        if (blocker != null) {
            Toast.makeText(this, PowerShare.messageFor(blocker),
                    Toast.LENGTH_SHORT).show();
        }
        sync();
    }

    private void sync() {
        boolean on = PowerShare.isRequestedOn();
        mSwitch.setChecked(on);
        mSwitch.setEnabled(on || PowerShare.blocker(this) == null);
        mStatus.setText(on ? R.string.status_requested : R.string.status_off);
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                value, getResources().getDisplayMetrics()));
    }
}
