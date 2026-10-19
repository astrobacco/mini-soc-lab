# Mini-SOC – Blue Team & Red Team Platform

A small but complete Security Operations Center (SOC) built only from free,
open-source tools. It runs as virtual machines on one computer and sets itself
up with a single command.

Final project (Abschlussprojekt) · ICT Warrior Academy · Felix Rechsteiner

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

| Tool | Address | User |
|---|---|---|
| OPNsense | https://localhost:8443 | root |
| Wazuh | https://localhost:8444 | admin |
| DFIR-IRIS | https://localhost:8445 | administrator |
| Greenbone | https://localhost:9392 | admin |

The lab uses self-signed certificates, so your browser will show a warning.

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
file. Open two terminals: one on `kali`, one on `wazuh`'s dashboard in the
browser. `target` runs DVWA (Damn Vulnerable Web Application) at
`http://10.10.20.10/dvwa/`, login `admin` / `password`, security level
already set to "low".

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
3. **SQL injection** – DVWA's SQLi page is deliberately broken; feed it a
   classic payload (either in the browser's "user ID" field or with curl):
   ```bash
   curl "http://10.10.20.10/dvwa/vulnerabilities/sqli/?id=1%27+OR+%271%27=%271&Submit=Submit" \
        -H "Cookie: security=low; PHPSESSID=<your session id>"
   ```
   or point `sqlmap` at the same URL for an automated run.
4. **File upload / web shell** – DVWA's upload page accepts a `.php` file
   with no checks; uploading one trips the file-integrity monitor instantly
   (the Wazuh agent on `target` watches `/var/www/html` in real time).
5. **Watch it land**: open the Wazuh dashboard
   (`https://localhost:8444`, *Security events*) and filter by rule group
   `minisoc_ids` or `web` – the port scan shows up as "Possible network scan",
   the SQL injection and file upload as high-severity Suricata/web alerts.
   Anything level 10 or higher appears automatically as a new alert in
   DFIR-IRIS (`https://localhost:8445`) with the attacker's IP already filled
   in as an indicator of compromise and `target` as the affected asset –
   ready to be turned into a documented case.

`~/EXERCISES.txt` on the `kali` VM has the short version of steps 1–3 as a
cheat sheet. `nmap`, `nikto`, `sqlmap`, `hydra` and `gobuster` are
pre-installed.

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
