/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.powershare;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.os.Process;

/**
 * Serves the inline switch of the injected Settings entry.
 *
 * <p>Protocol, taken from frameworks/base/packages/SettingsLib/Tile/src/com/
 * android/settingslib/drawer/{TileUtils,EntriesProvider}.java: Settings turns
 * the manifest's com.android.settings.switch_uri (authority only) plus
 * com.android.settings.keyhint into content://&lt;authority&gt;/&lt;method&gt;/
 * &lt;key&gt; and calls it. Only two methods matter here.
 *
 * <p>The provider has to be exported so the Settings process can reach it, so
 * every call is checked against uid system -- which AOSP Settings runs as
 * (android:sharedUserId="android.uid.system").
 */
public class PowerShareSwitchProvider extends ContentProvider {

    private static final String METHOD_IS_CHECKED = "isChecked";
    private static final String METHOD_ON_CHECKED_CHANGED = "onCheckedChanged";
    private static final String METHOD_GET_DYNAMIC_SUMMARY = "getDynamicSummary";

    private static final String EXTRA_SWITCH_CHECKED_STATE = "checked_state";
    private static final String EXTRA_SWITCH_SET_CHECKED_ERROR =
            "set_checked_error";
    private static final String EXTRA_SWITCH_SET_CHECKED_ERROR_MESSAGE =
            "set_checked_error_message";
    private static final String EXTRA_PREFERENCE_SUMMARY =
            "com.android.settings.summary";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (Process.SYSTEM_UID != android.os.UserHandle.getAppId(
                Binder.getCallingUid())) {
            throw new SecurityException("Only the system may drive power share");
        }

        Bundle result = new Bundle();
        switch (method) {
            case METHOD_IS_CHECKED:
                result.putBoolean(EXTRA_SWITCH_CHECKED_STATE,
                        PowerShare.isRequestedOn());
                break;

            case METHOD_ON_CHECKED_CHANGED: {
                boolean checked = extras != null
                        && extras.getBoolean(EXTRA_SWITCH_CHECKED_STATE);
                PowerShare.Blocker blocker =
                        PowerShare.set(getContext(), checked);
                if (blocker != null) {
                    result.putBoolean(EXTRA_SWITCH_SET_CHECKED_ERROR, true);
                    result.putString(EXTRA_SWITCH_SET_CHECKED_ERROR_MESSAGE,
                            getContext().getString(
                                    PowerShare.messageFor(blocker)));
                } else {
                    result.putBoolean(EXTRA_SWITCH_SET_CHECKED_ERROR, false);
                }
                break;
            }

            case METHOD_GET_DYNAMIC_SUMMARY:
                result.putString(EXTRA_PREFERENCE_SUMMARY,
                        getContext().getString(R.string.settings_summary));
                break;

            default:
                break;
        }
        return result;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) {
        throw new UnsupportedOperationException();
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection,
            String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }
}
