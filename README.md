# Mini-SOC – Blue Team & Red Team Platform

A small but complete Security Operations Center (SOC) built only from free,
open-source tools. It runs as virtual machines on one computer and sets itself
up with a single command.

Final project (Abschlussprojekt) · ICT Warrior Academy · Felix Rechsteiner

**New here? [`docs/TUTORIAL.md`](docs/TUTORIAL.md) is a single zero-to-everything
walkthrough: what this is, building it, your first attack by hand, and
watching it get caught.** Everything below is the full reference.

## What's inside

| VM | Tool | Job |
|---|---|---|
| `fw` | OPNsense | Firewall between the three lab networks |
| `wazuh` | Wazuh | SIEM: collects logs and alerts, correlates, raises alarms |
| `soc` | Greenbone CE + DFIR-IRIS | Vulnerability scanning · alert and case management |
| `sensor` | Suricata | Network IDS, listens silently on the server network |
| `target` | Ubuntu + Apache + DVWA | Practice server (the victim) |
| `kali` | Kali Linux | Attacker for red team exercises |

Serious Wazuh alerts (level 10+) automatically become alerts in DFIR-IRIS, with
the attacker IP and the affected machine already filled in.

```
   SOC 10.10.10.0/24          SERVERS 10.10.20.0/24        RED 10.10.66.0/24
   wazuh, soc, sensor   <-->        target          <-->        kali
                 \________________ fw (OPNsense) __________________/
```

The full attack → detection → response workflow, step by step, with exactly
where each piece of data gets written along the way:

![Mini-SOC workflow: attack, detection and response](docs/diagram-workflow.svg)

(source: [`docs/gen-diagram.py`](docs/gen-diagram.py) – re-run it after
changing the workflow it describes)

## Network isolation & safety

The lab is designed so that nothing inside it can reach your real network,
and the only way *in* is from your own computer:

- **Every VM has two network adapters.** NIC 1 is VirtualBox **NAT** – it
  only exists so Vagrant can SSH in and so the VMs can download packages
  during setup. NIC 2 (and NIC 3 on `sensor`) is a VirtualBox **"intnet"** –
  a fully isolated virtual switch that only exists between the lab's own
  VMs and never touches your host's physical network adapter at all. All
  the actual attack traffic (Kali → target, etc.) travels over intnet only.
- **NAT isolates outward, not sideways.** VirtualBox NAT works like a mini
  router: a VM can reach the real internet through it (needed for `apt
  install`, Docker pulls, `suricata-update`, etc.), but it has zero
  visibility onto other devices on your actual LAN/WiFi – it's hidden
  behind a private `10.0.2.0/24` subnet, not bridged onto your network.
  There is no bridged adapter anywhere in this project (the networking mode
  that *would* put a VM directly on your WiFi) – only NAT and intnet.
- **The web UIs you reach from your browser are localhost-only.** Every
  `forwarded_port` in the `Vagrantfile` (OPNsense :8443, Wazuh :8444,
  DFIR-IRIS :8445, Greenbone :9392) is explicitly bound to `host_ip:
  "127.0.0.1"`. That means only processes running on your own machine can
  reach them – not other devices on your WiFi, not anything "outside". It's
  the same mechanism as a local dev server: it looks like it's "exposed"
  because your own browser can reach it, but nothing external can.
- **Kali doesn't need internet for the exercises.** Ongoing internet access
  on `kali` (and the other VMs) is only used for package installation at
  build/update time. Every attack in `exercises/` and the DVWA walkthrough
  runs entirely over the isolated intnet networks.
- **What this setup does *not* protect against:** a vulnerability in
  VirtualBox itself (a hypervisor escape). That's a different class of risk
  from network exposure – unrelated to how this lab is wired – and the
  mitigation is keeping VirtualBox itself up to date, not VM networking
  changes.
- **Locking it down further:** if you want `kali` to have zero outbound
  internet access even during idle time, cut NIC 1 once the lab is built
  with `VBoxManage controlvm minisoc-kali setlinkstate1 off` (or unplug NIC
  1 in VirtualBox Manager). It'll still reach `target` fine for exercises;
  you'd just need to plug NIC 1 back in for `apt update`/`apt install`.

## Requirements

- Linux host with **VirtualBox 7** (Vagrant is installed automatically if missing)
- about **20 GB RAM** free for the full lab (less if you disable VMs in `lab.conf`)
- about **60 GB** disk space and a decent internet connection for the first build

## Quick start

```bash
git clone git@gitlab.ictwarrioracademy.ch:f.rechsteiner/minisoc-project.git
cd minisoc-project
./setup.sh
```

A clean build of the four core VMs (fw, wazuh, soc, sensor) took 26 minutes on
a laptop (i7-10510U, 32 GB RAM); target and kali add a few more minutes each.
Expect longer with a slow internet connection. At the
end it prints where to log in; the same overview is saved in `.lab/ACCESS.txt`
together with the generated lab password. Greenbone keeps loading its
vulnerability feed for another 30–60 minutes in the background.

| Tool | Address | User | New here? |
|---|---|---|---|
| OPNsense | https://localhost:8443 | root | [navigation guide](docs/guides/opnsense.md) |
| Wazuh | https://localhost:8444 | admin | [navigation guide](docs/guides/wazuh.md) |
| DFIR-IRIS | https://localhost:8445 | administrator | [navigation guide](docs/guides/dfir-iris.md) |
| Greenbone | https://localhost:9392 | admin | [navigation guide](docs/guides/greenbone.md) |
| DVWA (the practice target) | http://localhost:8446/dvwa/ | admin / password | see "Red team exercise" below |

The lab uses self-signed certificates, so your browser will show a warning on
the first five. DVWA is plain `http://` (it's the practice target, not a
tool you administer) and has its own fixed login, not the generated lab
password.
Each guide covers where the useful stuff actually is, what to filter/search
for in this specific lab, and what the exercise 01 walkthrough looks like in
that particular tool.

## Everyday use

```bash
./setup.sh status     # what is running + login overview
./setup.sh stop       # shut everything down (keeps the VMs)
./setup.sh            # start again / continue an interrupted build
./setup.sh destroy    # delete all VMs
vagrant ssh wazuh     # shell on a VM
```

Settings (which VMs, memory, versions, ports) are in [`lab.conf`](lab.conf).

## Red team exercise – try it yourself

A quick walkthrough to show the lab working end to end, attacker to case
file. `target` runs DVWA (Damn Vulnerable Web Application); you can reach
it two ways, and both feed the same detection pipeline:

- **By hand, in your own browser**: `http://localhost:8446/dvwa/`, login
  `admin` / `password`. Open **DVWA Security** (left menu) and set it to
  "low" first, or the deliberately-broken pages behave like fixed ones.
- **As the attacker**, from `kali` (`vagrant ssh kali`), reaching `target`
  the way an attacker actually would – over the lab network, through the
  firewall, not through your host.

### By hand

1. Log in, set security to "low".
2. Open **SQL Injection** (left menu). Type `1' OR '1'='1` into the User
   ID field and submit – the broken query returns every user instead of
   one. That's the vulnerability: user input gets concatenated straight
   into SQL with no sanitisation.
3. Open **File Upload**. Any `.php` file is accepted with no checks –
   upload one and you have a web shell; the Wazuh agent on `target`
   watches `/var/www/html` in real time and alerts the instant the file
   lands (`exercises/01-ftp-webshell` does the same thing in more depth,
   over FTP instead of DVWA's own upload form).

### As the attacker (`kali`)

```bash
vagrant ssh kali
```

1. **Recon** – find the target and what it's running:
   ```bash
   nmap -sV 10.10.20.10
   ```
2. **Web scan** – look for known paths and misconfigurations:
   ```bash
   nikto -h http://10.10.20.10/dvwa/
   ```
3. **SQL injection, automated**: point `sqlmap` at the vulnerable page –
   ```bash
   sqlmap -u "http://10.10.20.10/dvwa/vulnerabilities/sqli/?id=1&Submit=Submit" \
          --cookie="security=low; PHPSESSID=<a session id from your own login>" --batch
   ```
   (log in once via the browser first, copy the `PHPSESSID` cookie from
   your browser's dev tools – DVWA needs a logged-in session either way).

### Watch it land

Open the Wazuh dashboard (`https://localhost:8444`, *Security events*) and
filter by rule group `minisoc_ids` or `web` – a port scan shows up as
"Possible network scan", the SQL injection and file upload as
high-severity Suricata/web alerts. Anything level 10 or higher appears
automatically as a new alert in DFIR-IRIS (`https://localhost:8445`) with
the attacker's IP already filled in as an indicator of compromise and
`target` as the affected asset – ready to be turned into a documented
case. See [`docs/guides/wazuh.md`](docs/guides/wazuh.md) and
[`docs/guides/dfir-iris.md`](docs/guides/dfir-iris.md) if you're not sure
where to look.

`~/EXERCISES.txt` on the `kali` VM has the short version of the attacker
steps as a cheat sheet. `nmap`, `nikto`, `sqlmap`, `hydra` and `gobuster`
are pre-installed there.

## Guided blue-team exercises

[`exercises/`](exercises/) has full, scripted "zero to fixed" scenarios: a
vulnerability gets switched on, an attack script runs against it, and you
(the blue team) have to spot it in Wazuh, confirm it with a Greenbone scan
and fix it, without being told in advance what happened.

- [`exercises/01-ftp-webshell/`](exercises/01-ftp-webshell/) – anonymous FTP
  with a writable folder inside the web root leads to a PHP web shell and
  real code execution. Caught by Wazuh's file-integrity monitoring and two
  custom FTP rules, confirmed by Greenbone, fixed with one script.

## Documentation

The full project documentation is in
[`docs/MiniSOC_Documentation_EN.odt`](docs/MiniSOC_Documentation_EN.odt);
the original proposal (German) is in [`docs/proposal/`](docs/proposal/).
