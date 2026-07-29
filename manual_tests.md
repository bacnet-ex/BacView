# BacView – manual test checklist

Manual checks for features that need a real BACnet network, Wireshark, or desktop packaging. Automated coverage lives under `test/`; this list is what you still walk through by hand.

**Related UI**

| Area | Where |
|------|--------|
| Stack settings | Dashboard sidebar → Stack-Einstellungen → Erweitert |
| Log viewer | Dashboard topbar → Protokolle |
| Footer | All main pages (`#app-footer`) |
| Hex properties | Object properties table / write form |
| Skipped objects | Device page after load (`#device-skipped-objects`) |

---

## 2. Hex toggle for non-printable / binary properties

PARTIALLY VERIFIED! (I havent verified unknown properties keep existing behaviour)

**As built**

- Known character/octet strings: **Als Hex** / **Als Text** when non-printable (`hex_toggle?`).
- Writable simple text: hex mode sets `encoding=hex` and parses colon/plain hex on write.
- Unknown properties keep existing hex behaviour.

### Checklist

1. Object with description / character string containing `0x00` (or other non-printables).  
   → Text looks wrong/gibberish; **Als Hex** shows colon-hex (e.g. `61:00:62`).

2. Toggle to hex, change a byte, **Schreiben**, reload properties.  
   → Read-back matches written binary.

3. Normal printable UTF-8 description.  
   → No hex toggle (only when non-printable).

4. Unknown-properties panel: existing hex toggle still works.

---

## 5. Max APDU length (settings + per-device effective)

PARTIALLY VERIFIED! I havent verified a device with a lower APDU size.

**As built**

- Setting **50..1476** (raw).
- Per request: raw effective = `min(local_setting, remote_max_apdu)` when remote known.
- **`:max_apdu`** (ConfirmedServiceRequest): snap to largest BACnet constant **≤** effective raw (`50|128|206|480|1024|1476`).
- **`:max_apdu_length`** (`Client.send` / segmentation): **raw** effective (not snapped).
- No stack restart required for this setting.

### Checklist

1. Set max APDU to **480**, talk to a 1476 device on a constrained path.  
   Wireshark: confirmed requests show max APDU accepted consistent with **480** (encoded constant), not 1476.

2. Local **1476**, device I-Am **480**.  
   → Effective uses 480 (encode + send path capped by remote).

3. Local **1000**, remote **1476**.  
   → Encode snaps to **480**; send/segmentation length may use raw **1000** (not limited to enum for segment math).

4. Set **50**: small reads still work; oversized operations fail gracefully.

5. Save and restart app: setting persists in runtime settings JSON.
