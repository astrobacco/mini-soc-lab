# Problems solved along the way

Building this lab automatically brought up a steady stream of real
problems - most are the ordinary friction of automating six interdependent
VMs and a live attack/detection chain, a few are bugs in my own rules or
scripts. Every row below was a genuine issue hit while building or using
the lab, not a hypothetical. The essay
([`docs/MiniSOC_Documentation_EN.odt`](MiniSOC_Documentation_EN.odt))
covers the same ground in a few summary sentences, grouped by category -
this is the full, one-row-per-incident version, kept here instead of
there so the essay stays a readable document and this stays as long as it
needs to be.

New problems go here as a new row, oldest first.

| # | Problem | Root cause | Fix |
|---|---|---|---|
| 1 | FreeBSD got no network address | The emulated Intel NIC doesn't work under VirtualBox for this guest | Switched every machine to virtio network cards |
| 2 | OPNsense kept settings "on" that should be off | An empty tag in its config format already means "on" | Omit any flag that must stay off entirely |
| 3 | Vagrant couldn't reboot the firewall | No native reboot support for this FreeBSD box | Added a small custom Vagrant reboot capability |
| 4 | Docker image downloads stalled | Several parallel pulls over VirtualBox's NAT choke each other | Pull images one at a time, with retries |
| 5 | Greenbone containers reported "unhealthy" | Large databases still copying on first start | Wait and retry instead of failing the build |
| 6 | Suricata rules broke after a config change | An include file replaced an entire config section, not just the two values I meant to set | Set those two values directly instead of via include |
| 7 | VMs froze or stalled while booting | A stuck host process (the desktop's SSH agent) was using all available CPU | Lesson: check the host itself first when VMs misbehave |
| 8 | Kali kept losing its route to the lab | NetworkManager silently replaces the static route with a failed DHCP attempt - happened twice, including after a VirtualBox crash forced a non-standard restart | Auto-detect NetworkManager vs. netplan in provisioning; later hardened further by removing the competing network profile entirely and making the route reassert itself on every boot |
| 9 | Suricata alerts never reached Wazuh | A config self-test (run as root) left the alert log file root-owned, so the unprivileged service couldn't reopen it | Re-apply correct file ownership right before starting the service |
| 10 | vsftpd refused to behave while building the FTP exercise | In turn: an unneeded directive, a deliberate chroot safety check, then wrong upload permissions | Fixed each in turn; chained the custom Wazuh rule onto Wazuh's own built-in vsftpd rule set |
| 11 | A default credential (vagrant/vagrant) worked lab-wide | Every Vagrant box ships this password, reachable from anywhere on the lab network, not just my own host | Disabled SSH password authentication and locked the account on every machine |
| 12 | Most alerts in DFIR-IRIS were scanner noise, not attacks | Greenbone's own vulnerability-scan traffic looks exactly like an attacker to Wazuh's stock correlation rules - genuinely common in real SOCs; found in three separate passes as new gaps kept surfacing, including one stock rule that silently never fired because chaining onto a frequency rule doesn't intercept it | Downgrade, don't silence, anything sourced from the scanner; the stubborn rule needed overriding directly instead of chaining onto it |
| 13 | Couldn't open the practice app in my own browser | The target machine had no forwarded port at all, unlike the other tools | Added a 127.0.0.1-bound forwarded port, same pattern as the rest |
| 14 | Docs described the wrong Wazuh menu path | Written from general product knowledge rather than the actual installed version | Verified the real dashboard and pointed the docs at the one navigation path that's stable across versions |
| 15 | The hidden app's path was never found by recon | gobuster's wordlist only matches single words, not compound ones | Renamed the path to a single word, reverified with a real scan |
| 16 | hydra reported every brute-force attempt as a success | DVWA's CSRF token is single-use and hydra can't re-fetch it between attempts | A small script doing a real fetch-token-then-submit cycle per attempt |
| 17 | No detection existed for the login brute-force at all | Wazuh has no built-in decoder for a generic PHP login form, unlike SSH or FTP | A custom rule keyed on request volume instead of success or failure |
| 18 | A new Wazuh rule silently never fired | Wazuh only evaluates the one sibling rule that already matched, not every rule chained onto the same parent | Chained the new rule onto the rule that was actually matching the traffic |
| 19 | Core Suricata severity rules had never fired, ever, since this project began | Wazuh's built-in "srcip" condition doesn't read the plain field the generic JSON decoder actually produces | Matched the real field name directly; verified correct in both directions |
| 20 | Each exercise's attack step was one wrapper script | Defeats the point of a red-team exercise - the trainee should use the tools, not watch a script use them | Rewrote all three as hands-on, tool-by-tool walkthroughs |
| 21 | Exercise 03's Greenbone scan found nothing, twice | The scanner's SSH check skips its whole credential list once a random test username reports key-only auth - exactly what a correctly scoped account produces | Confirmed as a genuine, documented scanner limitation, not a bug, and kept as the honest result |
| 22 | DVWA never quite felt like a realistic target | Wanted an application I had actually built myself, with a brute-forceable login and an unrestricted upload | Replaced it with a hand-written "Employee Portal" app; this also turned up an honest gap between what a single manual request and an automated scan each trigger |
| 23 | Boot timeouts and desktop lockouts kept recurring | Leftover host load after a VM "finishes" booting, and once a genuine VirtualBox interface crash | Added a load-average gate and automatic retry between VM starts |
| 24 | Kali's screensaver came back after already being disabled once | A second, separate launch path (D-Bus service activation) bypassed the first fix entirely | Disabled the screensaver program at the binary level, closing every launch path at once |
| 25 | VirtualBox's own GUI crashed again, this time right when the host screen was locked for lunch | Qt6 frontend segfaults reacting to a host screen work-area change (confirmed via the crash's SIGSEGV signal and VBox.log) | No lab-side fix possible (a VirtualBox bug, not this project's) - `vagrant up --no-provision` recovers the VM in under a minute |
| 26 | Kali's lab route disappeared again right after restarting that aborted VM | Vagrant's own `private_network` step reapplies the interface on every `vagrant up`, landing after the boot-time route fix already ran once | A NetworkManager dispatcher script re-asserts the route on every interface change, not just once at boot |
| 27 | Kali's route vanished a fourth time, right before a live demo to a stakeholder | Whatever reconfigures the interface this time leaves no trace in NetworkManager's own log - no dispatcher event to react to at all | Stopped chasing the triggering mechanism; a 15-second systemd timer now re-asserts the route continuously, making the cause irrelevant |
| 28 | A VM hung for 16+ minutes mid-boot with no automatic recovery | Vagrant's post-boot network step has no timeout of its own, so `vagrant up` never returned - the existing poweroff-and-retry logic only triggers on a returned failure | Wrapped every `vagrant up` call in `setup.sh` with a timeout, so even an unbounded step can't block the whole build forever |
| 29 | A full attack ran with zero Wazuh alerts generated at all | `wazuh-manager`'s 45s startup timeout was too tight under real host load; systemd killed it mid-startup, leaving `remoted` never started while other sub-daemons ran on as orphans | Raised the timeout to a generous-but-bounded 180s via a systemd drop-in |
| 30 | The Wazuh dashboard said "server is not ready yet", twice on consecutive mornings | `wazuh-indexer`'s own 3-minute default startup timeout was also too tight under host contention - same bug as #29, just a different Wazuh service | Raised its timeout to 300s the same way, plus a provisioning check so a future recurrence isn't silent |
