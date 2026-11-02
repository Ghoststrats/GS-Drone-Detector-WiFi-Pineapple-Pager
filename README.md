# GS Drone Detector — Live Signal Tracker (WiFi Pineapple Pager)

**A passive Wi-Fi SSID-candidate detector, not a certified drone detector.** No versions shown on screen. Created for GhostStrats.

## Install

1. Stop the old detector on the Pager. Extract the ZIP on your computer.
2. Copy the ZIP's `payloads` folder into the Pager's `/mmc/root/`, merging folders and replacing only the existing GS Drone Detector files. **Do not delete the existing payloads folder.**
3. Verify `/mmc/root/payloads/user/reconnaissance/GS_Drone_Detector/payload.sh` exists and is executable (`chmod 755` if needed).
4. Open Payloads > User > Reconnaissance > GS Drone Detector.

## Live tracking

- **Default: one-second observation windows** on a usable monitor-mode interface (`wlan1mon` preferred). There is no extra sleep between capture windows.
- After detecting a candidate SSID, prints a fresh **10-block signal bar** and dBm reading after each window. Bars use a short moving average to reduce jitter.
- Signal labels are `WEAK SIGNAL`, `MODERATE`, `POSSIBLY NEAR`, and `MAY BE CLOSE`.
- Logs `TRACK HOLD` for two missing observations and clears after three consecutive misses. Prefers the previously tracked candidate if it remains visible.
- Native Pager `RINGTONE 'alert'` and `VIBRATE` are requested when a new candidate appears. Close-strength reminders use a cooldown (25 seconds by default) to avoid sound spam. Physical Pager sound hasn't been verified in this build.
- Status updates are printed in the **standard Pager payload LOG view**. This view is scroll-based, so live updates appear as successive lines rather than drawing over a fixed bar or making a new custom display.

**Important:** One-second capture windows are *not* a guaranteed one-second sweep of all Wi-Fi channels. Reception depends on the channel that the radio is currently monitoring, scan management by other Pager features, and beacon timing. A managed-mode `iw scan` can take several seconds; it does not refresh every second. This script does **not** change channels, take over the radio, or disable PineAP.

**Wi-Fi SSID names are not drone identification.** A name containing `DJI`, `DRONE`, etc. only suggests a drone-related Wi-Fi network. Not all drones emit these names; some networks may be controllers or spoofed APs. This payload does not decode Remote ID or confirm that the detected network is an aircraft. Stronger RSSI is **not** a measured distance, and direction, obstacles, transmit power, and antenna orientation affect readings. `MAY BE CLOSE` is a signal-strength category, not a distance estimate.

## Settings (optional environment variables)

- `GS_SCAN_WINDOW=1` — capture seconds for each monitor-mode window (1-10; default 1).
- `GS_WIFI_IFACE=wlan1mon` — override the automatically chosen monitor/managed interface.
- `GS_SOUND=0` — mute sounds. Default 1.
- `GS_VIBRATE=0` — turn off vibration. Default 1.
- `GS_CLOSE_REPEAT=25` — number of seconds between close-strength reminder alerts (minimum 10).
- `GS_DEMO=1 GS_MAX_ROUNDS=10 sh payload.sh` — simulated varying RSSI without radio. Pager sound commands only work if exposed by the launch environment.

Do not start multiple instances, as they compete for resources. Stop an existing payload before replacing it. No firmware flash and no network transmissions required.
