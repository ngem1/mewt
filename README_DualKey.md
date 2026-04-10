# Mewt — M5 Stack Chain DualKey (Windows)

This branch adds a **M5 Stack Chain DualKey** build of Mewt: OS-level microphone mute from the device, with **two NeoPixels** showing mute / hot / talking over **USB serial** (full behavior). **Bluetooth HID** can still act as a backup mute key, but the PC cannot drive the LEDs over BLE without extra software.

## What you need

- [M5 Chain DualKey](https://docs.m5stack.com/en/arduino/chain_dualkey/program) (USB/BLE switch set to **USB** for full Mewt)
- Windows PC (works **without administrator** for the usual Mewt PowerShell + DLL layout)
- Arduino IDE with **M5Stack** board support (**M5ChainDualKey**, board package ≥ 3.2.4) and **Adafruit NeoPixel** (≥ 1.15.2)
- The same **`AudioDeviceCmdlets.dll`** used by stock Mewt (see below — you do **not** need to run any `.exe`)

## Files in this repo (minimal set)

| Path | Purpose |
|------|--------|
| `code/m5stack_dualkey/mewt_dualkey.ino` | Flash to the DualKey |
| `code/m5stack_dualkey/mewt_dualkey.ps1` | Windows host loop (mute + levels → LED codes) |
| `code/m5stack_dualkey/setup_dualkey_port.ps1` | Create `mewt_com_port.txt` without the old self-extracting installer |
| `code/m5stack_dualkey/web/` | **Browser tester** — demo LEDs + optional Web Serial (see below) |

Copy **`AudioDeviceCmdlets.dll`** from `code/windows/mewt zip files/` into the **same folder** as `mewt_dualkey.ps1` (or install the module manually — see below).

## Web tester (before or after hardware)

The **`web/`** folder is a small static site that:

- **Without a DualKey:** Shows the same **left/right LED preview** as the firmware, lets you adjust **muted**, **simulated level**, and **talking threshold** (aligned with `mewt_dualkey.ps1`), optionally uses your **microphone** to drive “talking” when unmuted, and simulates a **key press** (toggles muted).
- **With a DualKey:** Uses the **Web Serial API** (Chrome or Edge) to open the DualKey’s **USB CDC** port at **9600 baud**, **stream** the current LED code on a timer (keeps the device’s 1s watchdog fed), **log** lines from the device (button toggles show as `0` / `1`), and **send** manual `0` / `1` / `2` / `101` for bring-up tests.

**Important:** On Windows, **only one program may use a COM port at a time**. Close **`mewt_dualkey.ps1`** (and anything else using that port) before connecting from the browser. For day-to-day muting, run the PowerShell script; use the web page for **practice**, **debugging**, and **LED checks**.

This page does **not** run `mewt_dualkey.ps1`; it only mirrors LED logic in the browser and (optionally) talks to the DualKey over **Web Serial**.

### How to run the web portal

You need a tiny **local web server** so the address bar shows **`http://localhost:…`**. **Do not** open `index.html` by double-clicking it (`file://` URLs block Web Serial and may break module loading).

1. **Clone or download** this repo and open a terminal.
2. **Change into the web folder** (from the repo root):

   | OS | Command |
   |----|--------|
   | macOS / Linux | `cd code/m5stack_dualkey/web` |
   | Windows (PowerShell or CMD) | `cd code\m5stack_dualkey\web` |

3. **Start a static server** on port **8080** (any free port is fine; change the URL below to match):

   | OS | Command |
   |----|--------|
   | macOS / Linux | `python3 -m http.server 8080` |
   | Windows | `py -m http.server 8080` or `python -m http.server 8080` |

   If you see “command not found”, install [Python](https://www.python.org/downloads/) from python.org or the Microsoft Store, then try again.

4. **Open a browser** to:

   **`http://localhost:8080`**

   Use **Chrome** or **Microsoft Edge** if you plan to use **Connect serial port** (Web Serial). Other browsers can still use **demo mode** (LED preview and sliders).

5. When you are done, go back to the terminal and press **Ctrl+C** to stop the server.

**Troubleshooting**

- **“Serial not available”** — Use Chrome or Edge; avoid `file://`; use `localhost` as above.
- **Port in use** — Pick another port, e.g. `python3 -m http.server 8090`, then open `http://localhost:8090`.
- **Optional:** If you have Node.js, from the same `web` folder you can run `npx --yes serve -l 8080` and open the URL it prints (choose the `http://localhost` link).

## LED meaning (USB)

Host sends one integer per line at **9600 baud**:

| Code | Meaning | Pixels (default) |
|------|---------|------------------|
| `0` | Microphone **muted** | Left off, **right green** |
| `1` | **Unmuted**, quiet | **Left red**, right off |
| `2` | **Unmuted**, speaking (level ≥ threshold) | **Both red** |
| `101` | Startup blink (green) | Same idea as stock Mewt |

If left/right look swapped on your unit, change pixel indices `0` and `1` in `applyLedCode()` in `mewt_dualkey.ino`.

## Install AudioDeviceCmdlets **without** running a `.exe`

Stock Mewt’s Windows `.exe` is only a convenience wrapper; the **logic** is: copy the **`.dll`** and import it in PowerShell.

### Option A — Next to the script (simplest)

1. Copy `AudioDeviceCmdlets.dll` into the folder that contains `mewt_dualkey.ps1`.
2. On first run, `mewt_dualkey.ps1` copies the DLL into your user module folder (same behavior as `mewt.ps1`).

### Option B — Manual module install (no Mewt folder copy)

1. Obtain `AudioDeviceCmdlets.dll` from this repo (`code/windows/mewt zip files/`) or from the upstream project [frgnca/AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) (release **.zip**, not an installer).
2. In **Windows PowerShell** or **PowerShell 7**, run (adjust the source path):

```powershell
$modDir = Join-Path (Split-Path $PROFILE) "Modules\AudioDeviceCmdlets"
New-Item -ItemType Directory -Path $modDir -Force
Copy-Item -Path "C:\path\to\AudioDeviceCmdlets.dll" -Destination $modDir
Get-ChildItem $modDir | Unblock-File
Import-Module AudioDeviceCmdlets
```

Use **`Split-Path $PROFILE`** so modules go to the right place for **PowerShell 5** vs **7** (paths differ).

### If DLL download or script execution is blocked

IT policy varies: you may be allowed **Git** or **ZIP extract** but not arbitrary `.exe`. A `.dll` + `.ps1` is often still usable. If **execution policy** blocks scripts, your options are whatever your org allows (e.g. `pwsh` from the Microsoft Store, signed scripts, or running the script from an allowed path). Mewt itself does not require elevation.

## COM port: do you pick it every time?

**No**, as long as Windows keeps a stable assignment.

- **Same USB port** on the same PC usually gets the **same COM number** (e.g. `COM5`) every time you plug in.
- If you change **physical port**, **hub**, or **driver**, the number **can** change — then update `mewt_com_port.txt`.
- **First-time setup:** run `setup_dualkey_port.ps1`, pick the port that appears when the DualKey is connected in **USB** mode.
- **Quick fix:** edit `mewt_com_port.txt` so it contains a single line like `COM5` (Device Manager → Ports).

The stock Mewt installer detects “new” COM ports by waiting for a count change; `setup_dualkey_port.ps1` is a small, **no-.exe** alternative.

## Build and flash the DualKey

1. Install **Arduino IDE**, add M5Stack board URL, install **M5ChainDualKey** and **M5Unified** / dependencies per [M5 Chain DualKey program](https://docs.m5stack.com/en/arduino/chain_dualkey/program).
2. Open `code/m5stack_dualkey/mewt_dualkey.ino`.
3. Select board **M5ChainDualKey**, connect USB (switch on USB), upload.

## Run the Windows host

1. Put in one folder: `mewt_dualkey.ps1`, `AudioDeviceCmdlets.dll`, and `mewt_com_port.txt` (from `setup_dualkey_port.ps1`).
2. Open PowerShell **in that folder**.
3. Run:

```powershell
.\mewt_dualkey.ps1
```

Optional third argument matches stock Mewt (`Zoom`, `Meet`, `Discord`) for app shortcuts.

### Low-latency behavior

`mewt_dualkey.ps1` is tuned for speed and triggers the Windows global mic toggle shortcut (**Win+Alt+K**) on key press, then reads the resulting mute state with `AudioDeviceCmdlets` for LED feedback. This gives faster mute/unmute response while keeping host state as the source of truth.

### Talking threshold

At the top of `mewt_dualkey.ps1`, **`$DUALKEY_TALK_THRESHOLD`** controls when level is treated as “talking” (LED code `2`). Increase it if ambient noise lights both reds; decrease if speech does not.

## Bluetooth (backup)

With the DualKey switch on **BLE**, the PC typically sees a **HID keyboard** only — **not** the USB serial link Mewt uses for LEDs. You can still map a key in **AutoHotkey** (or similar) to toggle mute; LED feedback would require a custom BLE service and a companion app, which this project does not provide.

## Acknowledgments

Mewt’s Windows host uses [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) (MIT). See the main [README](README.md) and [LICENSE](LICENSE).
