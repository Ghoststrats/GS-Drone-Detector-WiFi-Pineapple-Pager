# GS Drone Detector for Wi-Fi Pineapple Pager Payload

**A community-built Wi-Fi awareness payload by GhostStrats**

*Safety Is an Illusion.*

GS Drone Detector helps WiFi Pineapple Pager users observe **possible drone-related Wi-Fi networks** nearby. It looks for recognizable terms in broadcast network names (SSIDs), tracks one matching signal at a time, displays a live signal-strength bar, and requests audible/vibration alerts when supported by the Pager.

> **Important:** This is an experimental **candidate detector**, not a verified drone detector. A matching network name does not prove that a drone is present. Signal strength is not physical distance. This payload does not decode Remote ID, locate aircraft or pilots, or interfere with drones.

## Features

- **Drone-related Wi-Fi name matching:** Checks SSIDs for terms associated with DJI, Mavic, Matrice, Phantom, Avata, Tello, Skydio, Autel, Parrot, Fimi, FPV, and other drone-related names.
- **Live signal tracking:** Shows a 10-block signal meter and received signal strength in dBm where the adapter provides it.
- **Signal categories:** Displays `WEAK SIGNAL`, `MODERATE`, `POSSIBLY NEAR`, or `MAY BE CLOSE` as **signal-strength indicators only**.
- **Fast monitor-mode observations:** Uses consecutive **1-second capture windows** by default on an available monitor-mode interface. This is **not** a guaranteed 1-second scan of every Wi-Fi channel.
- **Smoothed readings:** Uses a small moving average to reduce sudden jumps in the displayed signal meter.
- **Signal-loss handling:** Holds a tracked signal during two missed observations and clears it after the third miss.
- **Pager alerts:** Requests the Pager's native `RINGTONE 'alert'` and `VIBRATE` actions when available, with a cooldown for repeat alerts.
- **No custom display required:** Results appear in the Pager's normal, scrolling payload log view.
- **Offline operation:** No cloud account, API key, or internet access is required for scanning.

## How it works

1. The payload discovers available Wi-Fi interfaces and prefers a usable **monitor-mode** interface (typically `wlan1mon`).
2. In monitor mode, it listens for Wi-Fi beacon and probe-response frames using `tcpdump`. When no suitable monitor interface is available, it may fall back to an `iw` managed-mode network scan.
3. It filters observed SSIDs for drone-related words. **These are clues, not verified aircraft identities.**
4. It selects the strongest matching signal with a readable RSSI, while preferring a previously tracked SSID if it is still visible.
5. The log updates the signal bar and warning category. New matches, escalation to a very strong signal, and certain continued strong readings can trigger alerts.

Monitor mode observes the channel the radio is currently monitoring; the payload **does not hop channels or take over the radio**. A managed-mode `iw scan` can take several seconds and may transmit probe requests. Actual update speed depends on the hardware, channel, driver, and Pager configuration.

## Requirements

- A **WiFi Pineapple Pager** with a compatible payload environment.
- An available Wi-Fi interface supporting monitor-mode packet capture or managed-mode scanning.
- `sh`, `iw`, and (for monitor mode) `tcpdump` and `timeout` accessible on the Pager.
- Appropriate permissions to inspect Wi-Fi interfaces and capture packets.
- The Pager's `LOG`, `RINGTONE`, and `VIBRATE` helpers for the corresponding native integrations; log output can fall back to standard text if `LOG` is unavailable.

**Compatibility note:** The script has not been fully validated on every Pager firmware version or radio configuration. Audible alerts and vibration depend on what the installed Pager runtime exposes.

## Installation

1. Download the project ZIP or GitHub repository and extract it on your computer.
2. Stop any running copy of GS Drone Detector on the Pager.
3. Copy the included **`payloads`** folder into **`/mmc/root/`** on the Pager, **merging** existing folders. Do **not** delete your existing `payloads` directory.
4. Confirm this file is present:

       /mmc/root/payloads/user/reconnaissance/GS_Drone_Detector/payload.sh

5. If necessary, make the script executable using a Pager terminal/SSH session:

       chmod 755 /mmc/root/payloads/user/reconnaissance/GS_Drone_Detector/payload.sh

6. On the Pager, go to **Payloads → User → Reconnaissance → GS Drone Detector** and launch it.

**No firmware flashing is needed.** The payload belongs under **Reconnaissance**, not the Alerts payload category.

## What the signal display means

| Display | Meaning |
| --- | --- |
| `WEAK SIGNAL` | A relatively weak received Wi-Fi signal. |
| `MODERATE` | A moderate received signal. |
| `POSSIBLY NEAR` | A stronger signal; actual distance is unknown. |
| `MAY BE CLOSE` | A very strong signal; **not** a verified distance or danger alert. |
| `TRACK HOLD` | The tracked SSID was temporarily missed. |
| `SIGNAL LOST` | The tracked SSID was cleared after repeated misses. |

A building, antenna direction, transmitter power, interference, reflections, or a moving radio can change RSSI without any change in the drone's position. Do not use these indicators for collision avoidance or safety-critical decisions.

## Optional configuration

These environment variables can be set before launching the script from a shell:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GS_SCAN_WINDOW` | `1` | Monitor-mode capture-window length in seconds (1–10). |
| `GS_WIFI_IFACE` | Auto-detect | Choose a specific interface, such as `wlan1mon`. |
| `GS_SOUND` | `1` | Set to `0` to disable ringtone requests. |
| `GS_VIBRATE` | `1` | Set to `0` to disable vibration requests. |
| `GS_CLOSE_REPEAT` | `25` | Minimum interval in seconds between persistent close-strength reminders (minimum 10). |
| `GS_MAX_ROUNDS` | `0` | Limit observation rounds; `0` means run until stopped. |
| `GS_DEMO` | `0` | Set to `1` for a simulated signal-tracking demonstration. |

To preview the tracker using **simulated** readings, from the payload directory run:

    GS_DEMO=1 GS_MAX_ROUNDS=10 sh payload.sh

The demo does **not** test the radio or prove that any real drone was detected. Native Pager alert helpers may not work when the script is launched outside the normal payload environment.

## Troubleshooting

**The payload does not appear in the Pager menu:** Confirm the exact directory name, the `payload.sh` filename, and the `reconnaissance` category path shown above. Check executable permissions.

**`NO SCAN INTERFACE`:** Check available adapters with `iw dev`. Ensure the required tools are installed and that the chosen interface is in a supported mode. Do not force an interface name that does not exist.

**No drone-related networks detected:** This may be normal. Many drones do not advertise a recognizable Wi-Fi SSID, and a single monitor-mode channel cannot see every nearby transmission. For a simple keyword-matching check, you can use an **owned** test hotspot named `DJI-TEST`; detecting it does not demonstrate aircraft detection.

**No beep or vibration:** Verify the Pager firmware/payload runtime supports `RINGTONE` and `VIBRATE`. These features were not confirmed on physical hardware in this build. You can turn them off using `GS_SOUND=0` or `GS_VIBRATE=0`.

**Updates are slower than 1 second:** The 1-second setting describes **monitor-mode observation windows**, not a complete all-channel scan. Managed-mode scans may be substantially slower.

**Replacing an older version:** Stop the running payload first, then replace the GS Drone Detector folder. Avoid running multiple copies simultaneously.

## Limitations and responsible use

- **Wi-Fi SSID keyword matches only:** It does not authenticate a drone, decode Remote ID, provide GPS positions, identify a pilot, or determine actual range.
- **Not universal detection:** Drones using proprietary links, hidden/renamed SSIDs, or unsupported radio protocols may never appear.
- **Passive capture versus scanning:** Monitor-mode capture listens for existing frames, but the managed-mode fallback may send normal Wi-Fi probe requests.
- **No interference:** The payload does not jam, disconnect, control, or issue commands to aircraft.
- **Not a safety device:** Do not depend on its signal categories for airspace surveillance or emergency decisions.

Only use the payload where you are authorized to operate the equipment and monitor wireless activity, and follow applicable laws and regulations.

## Project information

**Project:** GS Drone Detector for Wi-Fi Pineapple Pager Payload  
**Developer:** GhostStrats  
**Platform:** WiFi Pineapple Pager  
**Category:** Reconnaissance  
**Status:** Community/experimental payload  
**Affiliation:** Independent community project; not an official Hak5 product or endorsed by Hak5.

*Safety Is an Illusion.*
