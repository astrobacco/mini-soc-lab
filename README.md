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

## Documentation

The full project documentation is in
[`docs/MiniSOC_Documentation_EN.odt`](docs/MiniSOC_Documentation_EN.odt);
the original proposal (German) is in [`docs/proposal/`](docs/proposal/).
