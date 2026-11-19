# Mini-SOC: zero to everything

One path through the whole lab, in order: what it is, how to build it, how
to attack something on purpose, and how to watch yourself catch it. Every
other doc in this project goes deeper on one piece – this one is the map.

## 1. What is this, in one paragraph

Six small virtual machines that build themselves with one command. One is
a firewall splitting the lab into three isolated networks. One is a
deliberately vulnerable practice server. One is an attacker machine
(Kali). The other three are a SIEM (Wazuh), a case-management tool
(DFIR-IRIS) and a vulnerability scanner (Greenbone) – together, a small
Security Operations Center. You attack the practice server, the SOC tools
catch it, you look at what they caught.

```
   SOC 10.10.10.0/24          SERVERS 10.10.20.0/24        RED 10.10.66.0/24
   wazuh, soc, sensor   <-->        target          <-->        kali
                 \________________ fw (OPNsense) __________________/
```

The full step-by-step diagram (who talks to whom, what gets written where)
is in [`docs/diagram-workflow.svg`](diagram-workflow.svg), also embedded in
the main [`README.md`](../README.md).

## 2. Build it

```bash
git clone https://github.com/astrobacco/mini-soc-lab.git
cd mini-soc-lab
./setup.sh
```

Takes 30–45 minutes the first time (downloads VM images and packages).
When it's done, your login details are printed and saved to
`.lab/ACCESS.txt`:

| Tool | Address | User |
|---|---|---|
| OPNsense (firewall) | https://localhost:8443 | root |
| Wazuh (SIEM) | https://localhost:8444 | admin |
| DFIR-IRIS (cases) | https://localhost:8445 | administrator |
| Greenbone (vuln scanner) | https://localhost:9392 | admin |
| target (the practice server) | http://localhost:8446/ | — see step 4 |

The first five of those are **only reachable from your own computer**
(`127.0.0.1`-bound ports) – not your WiFi, not anywhere else. See the
"Network isolation & safety" section in [`README.md`](../README.md) if you
want the full reasoning. Your browser will warn about the certificate on
the first four – that's expected (self-signed), click through it.

Greenbone keeps downloading its vulnerability feed for another 30–60
minutes in the background after the build finishes – fine to ignore for
now, it matters later (step 7).

## 3. Open each tool once, just to see it

You don't need to learn these yet, just confirm they're all up:

- **OPNsense** → Dashboard. You'll see three network interfaces (SOC,
  SERVERS, RED) – that's the firewall separating the lab.
- **Wazuh** → should show 2 agents (`sensor`, `target`), both "Active".
- **DFIR-IRIS** → empty-ish Dashboard for now; this fills up once you
  attack something.
- **Greenbone** → empty Dashboard too, until you run a scan (step 7).
- **target** → an ordinary-looking small company site ("Northgate Defense
  Systems"). No login prompt, nothing obviously broken. That's
  deliberate – see step 4.

If anything looks wrong here, each has its own deeper guide:
[`docs/guides/opnsense.md`](guides/opnsense.md),
[`docs/guides/wazuh.md`](guides/wazuh.md),
[`docs/guides/dfir-iris.md`](guides/dfir-iris.md),
[`docs/guides/greenbone.md`](guides/greenbone.md).

## 4. Your first attack, by hand, in your own browser

No Kali, no terminal, no scripts yet – just click through it once so you
understand what's actually broken before automating anything.

1. Open **http://localhost:8446/**. A normal-looking small defense/
   logistics company site – Home, About, Services, Contact. Nothing here
   says "training app" anywhere. That's the point: a real target doesn't
   announce what's wrong with it either.
2. Try **http://localhost:8446/legacy/** directly. That gets you in – an
   old internal tool nobody decommissioned: a login page for an "Employee
   Portal". It's a small app hand-written for this lab, not a known
   training tool – see [`exercises/02-portal-sqli/`](../exercises/02-portal-sqli/README.md)
   for why that matters.
3. Its login is injectable. In the **Username** field, type:
   ```
   ' UNION SELECT 1,'admin','x'-- -
   ```
   leave the password blank (or anything), and submit. You're logged in –
   no password needed. That's the vulnerability: whatever you type gets
   pasted directly into a SQL query with no checks at all, and that query
   decides whether you're allowed in.
4. Once in, open **Submit a document** and upload any file, including a
   `.php` one – no checks at all, meaning you could upload a program that
   runs on the server, not just a document. Don't need to try this here;
   `exercises/01-ftp-webshell` (step 8 below) walks through exactly this,
   over FTP instead, start to finish including the fix – and lands in the
   same web root, at `/uploads/`, a second forgotten problem on the same
   "real" site.

That's it – you just found and exploited a real, common vulnerability
class (SQL injection, used here to bypass a login rather than just dump
data) by hand, no tools beyond a web browser. In step 5 you'll do the
"finding it" part properly, with actual recon tools instead of just
guessing the path.

## 5. The same attack, as an actual attacker

Now do recon and the same attack from `kali`, the way a real attacker
would – over the network, through the firewall, with real tools:

```bash
vagrant ssh kali
nmap -sV 10.10.20.10          # what's running on the target?
nikto -h http://10.10.20.10/  # any obviously bad paths/configs?
gobuster dir -u http://10.10.20.10/ -w /usr/share/wordlists/dirb/common.txt
# turns up /legacy/ - the hidden app you logged into by hand in step 4
```

Automate the SQL injection instead of typing the payload by hand:

```bash
sqlmap -u "http://10.10.20.10/legacy/login.php?username=admin&password=x" \
       --batch --dump -D portal -T users
```

`sqlmap` finds and confirms the injection, then dumps the real
credentials (`admin` / `Welcome1`) straight out of the database, in under
a second. Or just brute-force the login instead – the portal has no CSRF
token to fight (unlike DVWA, used in this lab until 2026-10-21), so
`hydra` works directly, no workaround script needed:

```bash
hydra -l admin -P ~/passwords.txt 10.10.20.10 http-post-form \
      '/legacy/login.php:username=^USER^&password=^PASS^:F=Login failed'
```

finds `admin` / `Welcome1` in a handful of tries.

`~/EXERCISES.txt` on `kali` has a short cheat sheet including the same
`sqlmap` run against the login page. `nmap`, `nikto`, `sqlmap`, `hydra`
and `gobuster` are all pre-installed there.

## 6. Watching it get caught

Open **Wazuh** (`https://localhost:8444`) → **Discover** (in the left
menu) → select the **`wazuh-alerts-*`** index pattern if it isn't already
selected. Widen the time range in the top-right corner if it looks empty
(defaults to the last 15 minutes). You should see entries like "Common
web attack", "Web server 400 error code", "SQL injection attempt", or
"Possible brute force attack against the portal login page" with a
timestamp matching what you just did.
Click one to expand it and see exactly what Wazuh saw.

Anything Wazuh rates level 10 or higher gets forwarded automatically to
**DFIR-IRIS** (`https://localhost:8445`) → **Alerts** – with your IP
already added as an indicator of compromise. Open one, then use
"escalate"/"merge into case" to turn it into an actual documented case.

Full detail on reading either dashboard, including exact filters for this
lab: [`docs/guides/wazuh.md`](guides/wazuh.md),
[`docs/guides/dfir-iris.md`](guides/dfir-iris.md).

## 7. Confirming with a vulnerability scan

Open **Greenbone** (`https://localhost:9392`) → **Scans → Tasks** → start
**"Scan target (incident response)"**. Takes about 20 minutes (it sits at
94–98% for most of that – normal, not stuck). When it's done, open
**Scans → Reports** and sort by severity – it independently confirms
things like the anonymous FTP misconfiguration from step 8 below, the
same way a real vulnerability assessment would (it does **not** catch the
portal's SQL injection or upload flaw – see step 8, those are
application-logic bugs no generic scanner can fingerprint). Full guide:
[`docs/guides/greenbone.md`](guides/greenbone.md).

## 8. A deeper exercise: attack → detect → confirm → fix → verify

Everything above shows pieces of the pipeline. For the complete loop –
including the fix and proof the fix worked – run
[`exercises/01-ftp-webshell/`](../exercises/01-ftp-webshell/README.md): a
real (not staged) misconfiguration gets switched on, then you drop a web
shell and get real code execution by hand (FTP client, `curl`, one
command at a time – no wrapper script), Wazuh catches it three independent
ways, Greenbone independently confirms the root cause, a fix script
remediates it, and a rescan proves it's actually fixed. Every number in
that doc (alert IDs, severities, IRIS alert numbers) came from actually
running it.

[`exercises/02-portal-sqli/`](../exercises/02-portal-sqli/README.md) is the
same loop with a deliberately different detection mechanism, against the
hand-written "Employee Portal" app from step 4: a login-bypass SQL
injection and an unrestricted file upload, with an honest twist – one
single, hand-crafted bypass request is almost invisible to this whole
stack (level 7, no Suricata hit at all), while the exact same bug run
through `sqlmap` lights up a dozen-plus alerts across Suricata and
Wazuh's correlation rules. Like exercise 01, Greenbone can't confirm
either flaw – an app-specific logic bug isn't something a generic
vulnerability scanner can fingerprint. Worth running right after 01 to
see the contrast.

[`exercises/03-ssh-bruteforce/`](../exercises/03-ssh-bruteforce/README.md)
rounds the set out: a forgotten service account with a weak SSH password,
caught by Wazuh's *built-in* brute-force detection (no custom rule needed,
unlike the other two) - and, like 02, not confirmable by Greenbone, but
for a third, different reason worth tracing down in the exercise itself.

## 9. Resetting / cleaning up

- **Just stop for the day**: `./setup.sh stop` (keeps everything built),
  `./setup.sh` to resume later – starts in seconds, doesn't rebuild.
- **Reset the exercise you just ran**: there's no synced folder into the
  VMs, so upload the whole exercise folder first (both `enable-vulnerability.sh`
  and `fix.sh` land together, in their own directory), then run `fix.sh`
  inside the VM:
  ```bash
  vagrant upload exercises/01-ftp-webshell /tmp/01-ftp-webshell target   # on the host
  vagrant ssh target                                                     # on the host
  sudo bash /tmp/01-ftp-webshell/fix.sh                                  # inside the VM
  ```
  restores the clean state (swap the exercise name for `02-portal-sqli` or
  `03-ssh-bruteforce` to reset one of those instead).
- **Full teardown**: `./setup.sh destroy` (asks first; deletes all VMs,
  keeps your generated lab password for next time).

## Where to go next

- [`README.md`](../README.md) – the full reference: requirements, every
  command, the network isolation model.
- [`docs/guides/`](guides/) – one deep-dive per dashboard.
- [`exercises/`](../exercises/) – full guided attack-to-fix scenarios.
- [`docs/MiniSOC_Documentation_EN.odt`](MiniSOC_Documentation_EN.odt) –
  the full written project documentation (why these tools, not others;
  what I learned building this).
