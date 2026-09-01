/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.powershare;

import android.graphics.drawable.Icon;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.widget.Toast;

/**
 * Quick Settings tile. This is the entry point the user is most likely to
 * reach: Settings gear -> edit tiles -> "Power sharing".
 */
public class PowerShareTileService extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        refresh();
    }

    @Override
    public void onClick() {
        super.onClick();

        boolean wantOn = !PowerShare.isRequestedOn();
        PowerShare.Blocker blocker = PowerShare.set(this, wantOn);
        if (blocker != null) {
            Toast.makeText(this, PowerShare.messageFor(blocker),
                    Toast.LENGTH_SHORT).show();
        }
        refresh();
    }

    private void refresh() {
        Tile tile = getQsTile();
        if (tile == null) {
            return;
        }

        boolean on = PowerShare.isRequestedOn();
        boolean available = on || PowerShare.blocker(this) == null;

        tile.setIcon(Icon.createWithResource(this, R.drawable.ic_powershare));
        tile.setLabel(getString(R.string.tile_label));
        tile.setSubtitle(getString(on ? R.string.state_on : R.string.state_off));
        tile.setState(!available ? Tile.STATE_UNAVAILABLE
                : on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.updateTile();
    }
}
