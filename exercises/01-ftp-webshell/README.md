# Exercise 01 – Anonymous FTP → Web Shell → Incident Response

A full "zero to fixed" blue team exercise: a real attack runs against
`target`, the trainee has to find it using only Wazuh (without being told
what happened), confirms the entry point with a Greenbone scan, and fixes it.
Every step below was actually run against the lab to produce this document –
the alert IDs, rule IDs and scan finding are real, not illustrative.

## The scenario

**Vulnerability:** `target` runs the genuine, current, fully patched Ubuntu
`vsftpd` package – nothing is backdoored or downgraded. The *configuration*
is what's broken: anonymous FTP login is enabled, and a folder inside the
web root (`/var/www/html/uploads`) is world-writable and reachable by the
anonymous FTP user. This is one of the most common real-world
misconfigurations there is – a writable upload folder sitting inside the web
root is an instant path from "anyone can FTP in" to "anyone can run code,"
because whatever gets uploaded can simply be requested over HTTP afterwards.

**Root cause, in the fictional sysadmin's own words:** "I set up anonymous
FTP as a quick drop-off for a file transfer script, made the folder writable
so uploads wouldn't fail, and when vsftpd refused to start because its
chroot root was writable, I widened the writable folder's scope rather than
figuring out why." That refusal (`500 OOPS: vsftpd: refusing to run with
writable root inside chroot()`) is a real, documented vsftpd safety check
that exists specifically to catch this exact mistake – working around it
without understanding it is itself a very common real failure mode, and part
of the lesson.

## Roles

- **Red cell / instructor:** runs `enable-vulnerability.sh` on `target`, then
  `attack.sh` on `kali`, without telling the trainee what was done.
- **Blue team / trainee:** only looks at Wazuh (and later Greenbone) to
  figure out what happened, then fixes it.

## Step 1 – Red cell: introduce the vulnerability

```bash
vagrant ssh target
sudo bash exercises/01-ftp-webshell/enable-vulnerability.sh
```

This writes a `/etc/vsftpd.conf` with `anonymous_enable=YES`,
`anon_upload_enable=YES`, `anon_umask=022` (so uploaded files are
world-readable – otherwise they'd be useless to anyone, which is itself why
this setting tends to travel together with anonymous upload in real
misconfigured servers) and a writable `/var/www/html/uploads` folder, then
restarts `vsftpd`.

## Step 2 – Red cell: run the attack

```bash
vagrant ssh kali
bash exercises/01-ftp-webshell/attack.sh
```

What it actually does, against the real lab:

```
[1/3] Anonymous FTP login + upload of minisoc_shell_11656.php into /uploads
Connected to 10.10.20.10.
220 (vsFTPd 3.0.5)
331 Please specify the password.
230 Login successful.
250 Directory successfully changed.
226 Transfer complete.

[2/3] Triggering the web shell over HTTP (whoami)
<pre>Mini-SOC exercise 01 web shell
www-data
</pre>
[3/3] Proving real code execution (writing a marker file via the shell)
<pre>Mini-SOC exercise 01 web shell
pwned by exercise-01
</pre>
```

Three real steps: anonymous FTP login, a PHP file landing inside the web
root, and that file executing shell commands as `www-data` – full remote
code execution, with nothing more than an FTP client and `curl`. The planted
file is a small, clearly-labelled training payload (`shell.php`, a one-line
`shell_exec($_GET['c'])`) – not disguised, not persistent beyond the
exercise.

## Step 3 – Blue team: find it in Wazuh

Open the Wazuh dashboard (`https://localhost:8444`) → **Security events**,
or tail the alerts directly. Three independent alerts fire for this one
attack – a good example of defence in depth, since no single one of them
depends on the others:

| # | Source | Rule | Level | What it tells you |
|---|---|---|---|---|
| 1 | File-integrity monitoring (`/var/www/html`, realtime) | `554` (`syscheck_entry_added`) | 7 | A new file, `/var/www/html/uploads/minisoc_shell_11656.php`, appeared – owned by `ftp:ftp`, mode `rw-r--r--`. The *ownership* is the giveaway: nothing on this box should be creating files as the `ftp` user. |
| 2 | `vsftpd` log | `100120` – *"FTP: anonymous login succeeded"* (custom rule, chained onto Wazuh's built-in `11402`) | 10 | An anonymous FTP session from `10.10.66.10` (the Kali box) logged in successfully. |
| 3 | `vsftpd` log | `100121` – *"FTP: a PHP file was uploaded via anonymous FTP – possible web shell!"* (custom rule, chained onto Wazuh's built-in `11404`) | 12 | The anonymous session that just logged in uploaded a `.php` file. |

Rules 2 and 3 are both level ≥ 10, so both are forwarded automatically to
**DFIR-IRIS** (`https://localhost:8445`) as new alerts with `10.10.66.10` as
the indicator of compromise and `target` as the affected asset – in this
real run they landed as IRIS alerts #817 and #818. Escalate them into a case
there to document the investigation.

At this point a trainee who has only seen these three alerts (not this
document) should already be able to answer: *what* happened (a file was
uploaded and is now a web shell), *how* (anonymous FTP), and *from where*
(`10.10.66.10`). What they can't yet prove from logs alone is *why the
server allowed it* – that's what the vulnerability scan is for.

Note on Suricata: the IDS sensor does **not** flag this attack – the ET
Open ruleset has no generic "unsophisticated custom PHP web shell" pattern,
only signatures for specific named shells. That's a deliberate, realistic
part of the lesson: network signatures miss novel/custom tooling, which is
exactly why host-based FIM matters as a second layer.

## Step 4 – Blue team: confirm the vulnerability with Greenbone

Open Greenbone (`https://localhost:9392`) → **Scans → Tasks**, and either
run the existing "Scan SERVERS network" task or – faster, and arguably more
realistic for an active incident where you already have a suspect host –
create a single-host task against just `10.10.20.10` with the **Full and
fast** scan config, so it isn't spending time on 253 addresses nobody's
using. A single-host scan with that config took about 8 minutes in this real
run.

Two findings on `target` directly confirm what Wazuh already pointed to:

| Finding | Severity | Port | Detail |
|---|---|---|---|
| **Anonymous FTP Login Reporting** | Medium (6.4) | 21/tcp | Logged in as `anonymous`/`ftp` and pulled the actual directory listing – including the world-writable `uploads` folder it found there. |
| **FTP Writeable Directories** | **Critical (10.0)** | 21/tcp | Names the exact path: `/uploads`. |

That's the confirmation step: it isn't just that *something* used FTP, it's
an independent tool – not Wazuh, not the attack script – actively probing
the service and reaching the same conclusion: anonymous login works, and a
folder inside the web root is writable through it. Two unrelated detection
methods (log-based alerting and an active vulnerability scan) agreeing on
the same root cause is exactly the kind of corroboration a real incident
write-up should have before calling a vulnerability confirmed.

## Step 5 – Blue team: fix it

```bash
vagrant ssh target
sudo bash exercises/01-ftp-webshell/fix.sh
```

This removes the planted web shell(s) and the `uploads` folder, and
restores the locked-down `vsftpd.conf` (`anonymous_enable=NO`,
`write_enable=NO`) that `provision/target/install.sh` ships by default.
Re-running the Greenbone scan afterwards confirms it: in this real run,
"Anonymous FTP Login Reporting" and "FTP Writeable Directories" both
disappeared from the report entirely – the only two FTP results left are the
generic, non-actionable "FTP Banner Detection" and "FTP Unencrypted
Cleartext Login" informational items. That's the loop closed: *vulnerable*
→ *exploited* → *detected* → *confirmed* → *fixed* → *verified fixed*, each
step backed by a real tool, not a step that was merely assumed to work.

## Files in this exercise

| File | Runs on | Purpose |
|---|---|---|
| `enable-vulnerability.sh` | `target` | Turns the misconfiguration on (idempotent, reversible). |
| `attack.sh` | `kali` | The attacker side: FTP upload + HTTP trigger. |
| `fix.sh` | `target` | Remediation: removes the shell, restores the locked-down config. |

## Why this design (and what it deliberately isn't)

This exercise intentionally avoids recreating a historic backdoored binary
(e.g. the famous vsftpd 2.3.4 trojan) – `vsftpd` here is the real, current,
fully patched Ubuntu package, only its *configuration* is weakened, and only
on demand. That is both safer (no legacy/unmaintained code with its own
unrelated bugs running on the box) and more realistic: misconfiguration,
not unpatched code, is the far more common real-world root cause of exactly
this kind of incident.
