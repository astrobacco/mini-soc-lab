# Navigating Greenbone (GSA / OpenVAS)

**URL:** https://localhost:9392 · **User:** `admin` · **Password:** in `.lab/ACCESS.txt`

Greenbone is the vulnerability scanner: it doesn't watch traffic like
Wazuh/Suricata, it actively probes `target` and tells you what's actually
wrong with it. It's also the slowest tool here by far – read the timing
note below before you assume something's stuck.

## First login

Accept the cert warning. You land on a **Dashboards** page full of empty
charts – ignore it, nothing has run yet on a fresh build. Go straight to
**Scans → Tasks**.

## Where things are

- **Scans → Tasks** – the two ready-made tasks for this lab:
  - **"Scan SERVERS network"** – sweeps the whole `10.10.20.0/24`.
    Thorough, but wastes a lot of time probing 253 addresses nobody's
    using.
  - **"Scan target (incident response)"** – single host (`10.10.20.10`)
    only. Use this one; same scan depth, much less wasted time, and more
    realistic for "I already have a suspect host."

  Click the ▶ (start) icon next to a task to run it. **This takes a long
  time** – in testing, a single-host "Full and fast" scan consistently
  took **~20 minutes**, with the progress bar sitting at 94–98% for most
  of the back half. That's normal OpenVAS behaviour (a handful of checks
  have long timeouts), not a hang. Don't stop and restart it unless it's
  genuinely been stuck at the same percentage for 10+ minutes.

- **Scans → Reports** – once a task finishes, its report lives here.
  Open it for a **results table**: each finding with host, port, severity
  (CVSS score + Low/Medium/High/Critical), and a name you can click into
  for the full description and a suggested fix.
- **Scans → Results** – the same findings but flattened across *all*
  reports/tasks – useful if you've run several scans and want one list.
- **Assets → Hosts** – what Greenbone has actually discovered alive on
  the network, with an aggregated vulnerability count per host.
- **Configuration → Targets / Scan Configs / Port Lists** – how the tasks
  above are defined. You generally won't need to touch these; they're set
  up by `provision/soc/greenbone-setup-scan.sh`. Useful if you want to
  build your own task against a different host or port range.

## Reading a report

Sort by **Severity** (click the column header) to see Critical/High first
– that's your triage order. Each finding's detail view has a
**Summary**, often **Impact**, and a **Solution** section with the actual
fix (upgrade, config change, etc.) – read that before going to patch
anything.

## A clean baseline scan (no exercise running)

With nothing deliberately toggled on, `target` should report essentially
nothing above Low severity. If a scan shows **"SSH Brute Force Logins With
Default Credentials Reporting"** or **"FTP Brute Force Logins With Default
Credentials Reporting"** with credentials `vagrant:vagrant` – that was a
real, lab-wide issue (every Vagrant box ships that default password,
reachable from the whole lab network, not just the host) found exactly
the way a scanner should, fixed in `provision/common/base.sh`
(password auth disabled, the account locked) and `provision/target/install.sh`
(vsftpd no longer accepts system-account logins at all). If you still see
it, `vagrant provision <vm>` the affected box and rescan.

## After running `exercises/01-ftp-webshell`

Run **"Scan target (incident response)"** while the vulnerability is
enabled. Expect two findings that directly confirm what Wazuh already
flagged:

| Finding | Severity | What it means |
|---|---|---|
| **Anonymous FTP Login Reporting** | Medium (6.4) | Logged in as `anonymous`/`ftp` and pulled the real directory listing – you can see the writable folder in the finding's own output. |
| **FTP Writeable Directories** | **Critical (10.0)** | Names the exact writable path: `/uploads`. |

After `fix.sh`, re-run the same task – both findings should be gone,
leaving only the generic, non-actionable "FTP Banner Detection" and "FTP
Unencrypted Cleartext Login" informational items. That disappearance is
your proof the fix actually worked, independent of Wazuh.

## Things that are *not* bugs

- An empty **Dashboards** page before any scan has run.
- The vulnerability feed keeps syncing in the background for 30–60
  minutes after a fresh `./setup.sh` build – a scan started *immediately*
  after build may find less than one started later. If results look
  thin on a brand-new lab, wait a bit and rescan.
- A scan stuck at a specific percentage for several minutes, especially
  in the 90s – see the timing note above.
