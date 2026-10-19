# Navigating DFIR-IRIS

**URL:** https://localhost:8445 · **User:** `administrator` · **Password:** in `.lab/ACCESS.txt`

IRIS is the case-management tool: the place alerts land automatically
once Wazuh decides they're serious (level ≥ 10), and where an analyst
turns "an alert happened" into a documented, investigated incident.

## First login

Accept the cert warning. You land on a **Dashboard**. IRIS is built
around two levels: **Alerts** (the inbox, no case needed) and **Cases**
(where real investigation/documentation happens). Most of the time you'll
move between the two.

## Where things are

- **Alerts** (top nav) – every alert Wazuh forwarded lands here
  automatically, unassigned, status "New". This is where you start after
  an exercise. Click an alert to see the full detail IRIS received:
  - **Title** = the Wazuh rule's description (e.g. "FTP: a PHP file was
    uploaded via anonymous FTP – possible web shell!")
  - **Severity** is pre-computed from the Wazuh alert level (≥13 →
    Critical, ≥10 → High, ≥7 → Medium, ≥4 → Low)
  - **Tags** include `wazuh`, `rule:<id>`, `agent:<name>`, and
    `mitre:<technique id>` where applicable – useful for filtering the
    alert list
  - **IOCs** tab on the alert: the attacker's IP is already added as an
    `ip-src` indicator, automatically
  - The raw Wazuh alert JSON and matched log line are in the description,
    so you don't need to cross-reference Wazuh for basic triage
- **Cases** (top nav) – create one (or merge an alert into one) to do the
  actual write-up. A case has its own left-side tabs:
  - **Summary** – free-text narrative of the incident
  - **Timeline** – chronological events you add as you investigate
  - **IOCs** – indicators (carries over automatically when you escalate
    an alert into the case)
  - **Assets** – affected machines (add `target` here manually, or it
    may already be implied by the alert's agent context)
  - **Tasks** – a simple to-do list for the investigation itself
  - **Notes** – free-form scratch space

## Turning an alert into a case

From the **Alerts** list, open an alert → there's an **escalate**/**merge
into case** action (new case, or add to an existing one). This copies the
alert's IOCs and context across. Do this for anything you've actually
confirmed is real (after checking Wazuh/Greenbone) rather than for every
single alert – IRIS is meant to hold documented incidents, not raw noise.

## After running `exercises/01-ftp-webshell`

Expect two new alerts in the inbox: one titled *"FTP: anonymous login
succeeded"* (High) and one titled *"FTP: a PHP file was uploaded via
anonymous FTP – possible web shell!"* (Critical) – both already carrying
`10.10.66.10` (Kali) as an `ip-src` IOC. A realistic write-up: open a case,
escalate both alerts into it, add `target` as the affected asset, use the
Greenbone findings (see the Greenbone guide) as corroborating evidence in
the Timeline, and close the case referencing `fix.sh` as the remediation.

## Things that are *not* bugs

- A new alert/case belongs to the default customer (there's only one
  configured in this lab) – you won't need to create or pick a customer.
- IRIS alerts stay "New" until *you* triage them; Wazuh doesn't update
  their status after sending.
