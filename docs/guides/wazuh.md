# Navigating Wazuh

**URL:** https://localhost:8444 · **User:** `admin` · **Password:** in `.lab/ACCESS.txt`

Wazuh is the SIEM: it collects logs/alerts from every agent (`sensor`,
`target`), correlates them with rules, and is the first place to look when
investigating anything. It is also the *noisiest* UI of the four – here's
how to cut through that.

## First login

Accept the certificate warning (self-signed). The left-hand menu you land
on is the *platform's* own menu (Discover, Dashboards, Visualize,
Reporting, Alerting, Anomaly detection, Maps, Notifications) – Wazuh's own
interface is a separate app on top of it, opened via the **Wazuh logo** in
the top-left corner (not nested under any of those). Click it to get to
the actual Wazuh home page (agent status, modules, etc.).

## The most reliable way to see alerts: Discover

Wazuh's own UI is where the polish is, but it changes labels/layout
between versions. The one thing that's stable regardless of version: the
platform's native **Discover** app (already in that left-hand menu you're
looking at) reading the **`wazuh-alerts-*`** index pattern – every alert
Wazuh ever raised, in one searchable table, already pre-registered in this
lab. Open **Discover**, check the index pattern selector (top-left of the
page, under the search bar) says `wazuh-alerts-*`, then use the search bar
below for everything in the table further down.

## The one thing that trips everyone up: the time filter

Top-right corner, every screen: a **date/time range picker** (defaults to
"Last 15 minutes" or similar). If a screen looks empty after you *know*
something just happened, this is almost always why. Widen it ("Last 24
hours" or a custom range covering your exercise) before concluding nothing
fired.

## Where things are

- **Discover** (`wazuh-alerts-*`, see above) – the main alert feed,
  sortable/filterable table, this is where you'll spend most of your
  time. Each row expands to the full alert (rule id, level, MITRE
  mapping, raw log).
- **The Wazuh home page** (click the Wazuh logo, top-left) – from there,
  Wazuh's own modules are available: an endpoints/agent status summary
  (should show `sensor` and `target` as **Active** – if either shows
  anything else, check
  `vagrant ssh <sensor|target> -c "sudo systemctl status wazuh-agent"`),
  a vulnerability-detection view, and (usually under a "Server
  management" or similar section) the loaded rule set, including this
  project's own custom rules (IDs `100100`–`100121`, group `minisoc,` –
  see `provision/wazuh/minisoc_rules.xml` to read them directly instead
  of hunting for them in the UI). Exact labels and layout here are the
  part most likely to have moved since this was written – if something
  mentioned isn't where this guide says, `Discover` above always works as
  a fallback that doesn't depend on Wazuh's own UI structure at all.

## Filtering for *this lab's* alerts specifically

In **Discover**, with the `wazuh-alerts-*` index pattern selected, use the
search bar (KQL-style):

| What you're looking for | Filter |
|---|---|
| Everything from the custom Mini-SOC ruleset | `rule.groups: minisoc_ids OR rule.groups: minisoc_ftp OR rule.groups: ftp` |
| Suricata/IDS alerts | `rule.groups: ids` |
| A possible network scan | `rule.id: 100110` |
| File-integrity (new/changed files on `target`'s web root) | `rule.groups: syscheck` (added = rule `554`, modified = `550`, deleted = `553`) |
| Anonymous FTP login (exercise 01) | `rule.id: 100120` |
| PHP web shell uploaded via FTP (exercise 01) | `rule.id: 100121` |
| Only alerts from one agent | `agent.name: target` (or `sensor`) |
| Only alerts that got forwarded to IRIS | `rule.level >= 10` |
| Exclude Greenbone's own scan traffic (see below) | `NOT data.srcip: 10.10.10.20 AND NOT rule.groups: minisoc_scanner_noise` |

Click any row to expand it – the raw `full_log` field is usually more
informative than the summary, especially for FIM events (shows exact
old/new file hashes, owner, permissions).

## After running `exercises/01-ftp-webshell`

Expect, in this order: a `syscheck` "file added" alert (rule `554`) the
moment the shell lands, then `100120` (anonymous login) and `100121`
(PHP upload) from the `vsftpd` log a few seconds later. All three come
from the same attack but via independent detection paths – that's the
point of the exercise (see its own README for why).

## Things that are *not* bugs

- A handful of `apache`/web-server alerts at low levels during normal use
  of the DVWA app hidden at `/legacy/` are expected noise, not incidents.
- Wazuh's own `000` (server) agent entry is itself, not a monitored host –
  ignore it.
- The dashboard can take 10–20 seconds to reflect a very recent alert;
  it's not real-time to the second.
- **If the dashboard is a wall of "multiple web server 400 error codes" /
  "multiple common web attacks" / "multiple XSS attempts" / Suricata
  log4j-and-XSS alerts and almost nothing else is visible**: that's
  Greenbone (`soc`, `10.10.10.20`) scanning `target` – its vulnerability
  checks look exactly like an attacker to the stock correlation rules,
  and a single "Full and fast" scan can generate thousands of them. This
  is now tuned down by design (custom rules 100100/100101/100110 plus the
  complete 100122–100128 family) rather than removed entirely, so it
  stays visible at a low level – labelled, in the `minisoc_scanner_noise`
  group – instead of escalating to DFIR-IRIS as if it were a real
  incident. If you're still seeing it flood the screen, make sure `wazuh`
  has been reprovisioned since these rules were added.
