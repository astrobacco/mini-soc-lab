# Navigating Wazuh

**URL:** https://localhost:8444 · **User:** `admin` · **Password:** in `.lab/ACCESS.txt`

Wazuh is the SIEM: it collects logs/alerts from every agent (`sensor`,
`target`), correlates them with rules, and is the first place to look when
investigating anything. It is also the *noisiest* UI of the four – here's
how to cut through that.

## First login

Accept the certificate warning (self-signed). You land on an **Overview**
page with module tiles. Ignore most of them for now; you'll mainly live in
two places: **Security events** and **Agents**.

## The one thing that trips everyone up: the time filter

Top-right corner, every screen: a **date/time range picker** (defaults to
"Last 15 minutes" or similar). If a screen looks empty after you *know*
something just happened, this is almost always why. Widen it ("Last 24
hours" or a custom range covering your exercise) before concluding nothing
fired.

## Where things are

- **Agents** (left sidebar) – should show `sensor` and `target` as
  **Active**. If either shows anything else, that agent isn't reporting
  and nothing it should catch will appear anywhere else in this UI. Check
  `vagrant ssh <sensor|target> -c "sudo systemctl status wazuh-agent"`.
- **Explore → Security events** – the main alert feed, sortable/filterable
  table, this is where you spend most of your time. Each row expands to
  the full alert (rule id, level, MITRE mapping, raw log).
- **Explore → Discover** – raw/low-level log search (not just alerts) if
  you need to see something that didn't rise to an alert.
- **Threat intelligence → MITRE ATT&CK** – maps fired alerts to MITRE
  techniques; several of this lab's custom rules are tagged (e.g. T1046
  recon, T1078 valid accounts, T1505.003 web shell).
- **Server management → Rules** – search/browse the loaded rule set,
  including this project's own (IDs `100100`–`100121`, group `minisoc,`
  – see `provision/wazuh/minisoc_rules.xml`). Useful for checking a rule's
  exact match conditions instead of guessing.

## Filtering for *this lab's* alerts specifically

In **Security events**, use the search bar (KQL-style) or the filter
builder:

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

- A handful of `apache`/web-server alerts at low levels during normal DVWA
  use are expected noise, not incidents.
- Wazuh's own `000` (server) agent entry is itself, not a monitored host –
  ignore it.
- The dashboard can take 10–20 seconds to reflect a very recent alert;
  it's not real-time to the second.
