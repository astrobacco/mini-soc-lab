# Navigating OPNsense

**URL:** https://localhost:8443 · **User:** `root` · **Password:** in `.lab/ACCESS.txt`

OPNsense is the firewall/router sitting between all three lab networks.
You won't spend much time here day-to-day, but it's the right place to
check *what traffic actually crossed a boundary* and to see the rules that
enforce the lab's segmentation.

## First login

Accept the cert warning. You land on the **Dashboard** – widgets for
system status, interfaces, etc. Mostly skippable.

## The three interfaces, and what they're actually called here

OPNsense's interface names are generic (`LAN`, `OPT1`, `OPT2`), but this
lab's config gives each one a clear description that shows up throughout
the UI:

| OPNsense interface | Description shown in UI | Actual network |
|---|---|---|
| LAN | **SOC** | `10.10.10.0/24` – wazuh, soc, sensor |
| OPT1 | **SERVERS** | `10.10.20.0/24` – target |
| OPT2 | **RED** | `10.10.66.0/24` – kali |

**Interfaces → Overview** shows all three, their link state and traffic
counters – a quick sanity check that a VM is actually plugged in and
passing traffic.

## Where things are

- **Firewall → Rules** – one tab per interface. This is the actual
  enforcement: open the **SERVERS** tab to see "Wazuh agents to manager"
  (allowed), "block everything else into the SOC" (deny), "no access to
  firewall itself" (deny), "outbound – logged" (allow, logged). Open
  **RED** to see the two block rules (no reaching the SOC, no reaching the
  firewall) and the final logged allow-everything-else rule that lets Kali
  attack `target`.
- **Firewall → Log Files → Live View** – the most useful screen in this
  UI for this lab. Real-time feed of every rule match, including the
  *logged* ones. Filter by interface (SERVERS or RED) to watch Kali's
  traffic cross the boundary live during an exercise, or to confirm a
  blocked packet actually got blocked (e.g. try to reach the SOC from RED
  – you should see it logged as blocked here, never reach Wazuh).
- **Interfaces → Diagnostics → Packet Capture** – if you need to actually
  inspect packet contents rather than just rule matches (rarely needed for
  this lab; the `sensor` VM's Suricata already does full IDS on the
  SERVERS segment).

## Reading the rules you'll actually use

Every rule in this lab was generated from
`provision/firewall/config.xml.tpl` – if the GUI's wording is confusing,
that file's `<descr>` tags are the authoritative plain-English version of
what each rule does, written for exactly this reason.

## What to check during/after a red-team exercise

1. **Firewall → Log Files → Live View**, filter interface = RED: confirms
   Kali's attack traffic really left RED and was allowed through toward
   SERVERS (it's logged, not silently passed).
2. Try the same from SOC → RED or RED → SOC: should show up as **blocked**
   – this is the segmentation actually working, not just configured.
3. If something unexpected gets through or gets blocked, the rule that
   matched is named in the log line itself – cross-reference it against
   **Firewall → Rules** on the relevant interface.

## Things that are *not* bugs

- The WAN interface only allows the host machine (`10.0.2.2`, the
  VirtualBox NAT gateway) – this is intentional, nothing on the internet
  can reach OPNsense's management UI.
- Occasional "state table" or "gateway" warnings on the Dashboard are
  normal for a lab firewall with no real WAN uplink beyond NAT.
