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
git clone git@gitlab.ictwarrioracademy.ch:f.rechsteiner/minisoc-project.git
cd minisoc-project
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
| DVWA (the practice target) | http://localhost:8446/dvwa/ | admin / password |

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
- **DVWA** → a login page. This is the one you're about to attack.

If anything looks wrong here, each has its own deeper guide:
[`docs/guides/opnsense.md`](guides/opnsense.md),
[`docs/guides/wazuh.md`](guides/wazuh.md),
[`docs/guides/dfir-iris.md`](guides/dfir-iris.md),
[`docs/guides/greenbone.md`](guides/greenbone.md).

## 4. Your first attack, by hand, in your own browser

No Kali, no terminal, no scripts yet – just click through it once so you
understand what's actually broken before automating anything.

1. Open **http://localhost:8446/dvwa/**, log in as `admin` / `password`.
2. Left menu → **DVWA Security**. It should already say "Low" (that's the
   lab's default) – if not, set it to Low and submit.
3. Left menu → **SQL Injection**. There's one text box, "User ID". Type:
   ```
   1' OR '1'='1
   ```
   and submit. Instead of one user, you get every user in the database
   back. That's the vulnerability: whatever you type gets pasted directly
   into a SQL query with no checks at all.
4. Left menu → **File Upload**. Any file is accepted, including a `.php`
   one – meaning you could upload a program that runs on the server, not
   just a picture. Don't need to try this here; `exercises/01-ftp-webshell`
   (step 8 below) walks through exactly this, over FTP instead, start to
   finish including the fix.

That's it – you just found and exploited a real, common vulnerability
class (SQL injection) by hand, no tools beyond a web browser.

## 5. The same attack, as an actual attacker

Now do recon and the same SQLi from `kali`, the way a real attacker would
– over the network, through the firewall, with real tools:

```bash
vagrant ssh kali
nmap -sV 10.10.20.10              # what's running on the target?
nikto -h http://10.10.20.10/dvwa/ # any obviously bad paths/configs?
```

`~/EXERCISES.txt` on `kali` has a short cheat sheet including an automated
`sqlmap` run against the same SQL injection page. `nmap`, `nikto`,
`sqlmap`, `hydra` and `gobuster` are all pre-installed there.

## 6. Watching it get caught

Open **Wazuh** (`https://localhost:8444`) → **Discover** (in the left
menu) → select the **`wazuh-alerts-*`** index pattern if it isn't already
selected. Widen the time range in the top-right corner if it looks empty
(defaults to the last 15 minutes). You should see entries like "Common
web attack" or "Web server 400 error code" with a timestamp matching what
you just did. Click one to expand it and see exactly what Wazuh saw.

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
things like DVWA's weak security and any misconfigurations, the same way
a real vulnerability assessment would. Full guide:
[`docs/guides/greenbone.md`](guides/greenbone.md).

## 8. A deeper exercise: attack → detect → confirm → fix → verify

Everything above shows pieces of the pipeline. For the complete loop –
including the fix and proof the fix worked – run
[`exercises/01-ftp-webshell/`](../exercises/01-ftp-webshell/README.md): a
real (not staged) misconfiguration gets switched on, an attack script
drops a web shell and gets real code execution, Wazuh catches it three
independent ways, Greenbone independently confirms the root cause, a fix
script remediates it, and a rescan proves it's actually fixed. Every
number in that doc (alert IDs, severities, IRIS alert numbers) came from
actually running it.

## 9. Resetting / cleaning up

- **Just stop for the day**: `./setup.sh stop` (keeps everything built),
  `./setup.sh` to resume later – starts in seconds, doesn't rebuild.
- **Reset the exercise you just ran**: `vagrant ssh target` then
  `sudo bash exercises/01-ftp-webshell/fix.sh` restores the clean state.
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
