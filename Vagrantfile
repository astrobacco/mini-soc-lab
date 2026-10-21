# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Mini-SOC lab - all virtual machines are defined here.
#
# Don't run "vagrant up" by hand the first time - use ./setup.sh, which
# creates the lab passwords, checks your machine and starts everything in the
# right order. After that, normal Vagrant commands work (vagrant halt,
# vagrant up, vagrant ssh <name>, ...).
#
#   Network            Segment          Who lives there
#   minisoc-soc        10.10.10.0/24    fw .1, wazuh .10, soc .20, sensor .30
#   minisoc-servers    10.10.20.0/24    fw .1, target .10   (sensor sniffs here)
#   minisoc-red        10.10.66.0/24    fw .1, kali .10
#
# Every VM also has a VirtualBox NAT adapter (NIC 1) which Vagrant uses for
# SSH and the VMs use for downloads. Traffic *between* the lab networks
# always goes through the OPNsense firewall.

ROOT = File.dirname(__FILE__)

# Reads simple KEY=value files (lab.conf, .lab/secrets.env).
def read_env_file(path)
  return {} unless File.exist?(path)
  File.readlines(path).each_with_object({}) do |line, env|
    next unless line.chomp =~ /\A\s*([A-Z0-9_]+)=(.*)\z/
    env[$1] = $2.sub(/\s+#.*\z/, "").strip.sub(/\A(["'])(.*)\1\z/, '\2')
  end
end

# Vagrant can reboot Linux guests during provisioning, but not FreeBSD ones.
# The firewall needs it (opnsense-bootstrap replaces the kernel), so this adds
# the missing "reboot" capability: note the boot time, reboot, and wait until
# the machine answers with a different boot time.
module MiniSocFreeBSDReboot
  def self.boot_time(machine)
    out = +""
    machine.communicate.execute("sysctl -n kern.boottime") { |_type, data| out << data }
    out.strip
  end

  def self.reboot(machine)
    before = boot_time(machine)
    machine.communicate.sudo("(sleep 2; shutdown -r now) >/dev/null 2>&1 &")
    machine.ui.info("Rebooting (the first OPNsense boot takes a few minutes)...")
    deadline = Time.now + machine.config.vm.boot_timeout
    loop do
      sleep 10
      begin
        return if machine.communicate.ready? && boot_time(machine) != before
      rescue StandardError
        # SSH is down while the machine reboots - keep waiting
      end
      raise "firewall did not come back after reboot" if Time.now > deadline
    end
  end
end

class MiniSocFreeBSDRebootPlugin < Vagrant.plugin("2")
  name "minisoc-freebsd-reboot"
  guest_capability("freebsd", "reboot") { MiniSocFreeBSDReboot }
end

CONF    = read_env_file(File.join(ROOT, "lab.conf"))
SECRETS = read_env_file(File.join(ROOT, ".lab", "secrets.env"))

if SECRETS.empty? && !ARGV.include?("destroy") && !ARGV.include?("status")
  abort "Lab secrets are missing (.lab/secrets.env). Run ./setup.sh instead of 'vagrant up'."
end

def conf(key, default = nil)
  ENV.fetch(key) { CONF.fetch(key, default) }
end

def enabled?(name)
  conf("ENABLE_#{name.upcase}", "true") == "true"
end

# Values every provisioning script gets as environment variables.
PROVISION_ENV = SECRETS.merge(
  "WAZUH_VERSION"     => conf("WAZUH_VERSION"),
  "IRIS_VERSION"      => conf("IRIS_VERSION"),
  "OPNSENSE_RELEASE"  => conf("OPNSENSE_RELEASE"),
  "WAZUH_MANAGER"     => "10.10.10.10",
  "LAB_DOMAIN"        => "minisoc.lab",
)

Vagrant.configure("2") do |config|
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "virtualbox" do |vb|
    vb.default_nic_type = "virtio"
    vb.linked_clone = true
    vb.customize ["modifyvm", :id, "--groups", "/Mini-SOC"]
    vb.customize ["modifyvm", :id, "--audio-enabled", "off"]
  end

  # Small helper so every VM is described the same way. Also overrides the
  # upstream box's own VirtualBox "Description" field (bento/kalilinux boxes
  # ship one that just says the vagrant/vagrant default login) - found
  # stale and misleading: on the Linux VMs base.sh locks that account and
  # disables SSH password auth lab-wide, so there is no VM login password
  # at all any more, only `vagrant ssh <name>` (key-based, automatic) and
  # the single generated lab password for the web dashboards.
  def vm_resources(machine, name, memory, cpus)
    machine.vm.provider "virtualbox" do |vb|
      vb.name   = "minisoc-#{name}"
      vb.memory = memory
      vb.cpus   = cpus
      vb.customize ["modifyvm", :id, "--description",
        "Mini-SOC lab VM. No console/SSH password - use 'vagrant ssh #{name}' " \
        "from the host (key-based). Web dashboards use the single lab " \
        "password in .lab/ACCESS.txt."]
    end
  end

  # Shared helper scripts land in /opt/minisoc on every Linux VM.
  def linux_base(machine, segment_ip, gateway)
    machine.vm.provision "common", type: "file", source: "#{ROOT}/provision/common", destination: "/tmp/minisoc-common"
    machine.vm.provision "base", type: "shell", path: "#{ROOT}/provision/common/base.sh",
      env: PROVISION_ENV.merge("LAB_IP" => segment_ip, "LAB_GATEWAY" => gateway)
  end

  # --------------------------------------------------------------------------
  # fw - OPNsense firewall / router (built from FreeBSD by opnsense-bootstrap)
  # --------------------------------------------------------------------------
  config.vm.define "fw", primary: true do |fw|
    fw.vm.box = "bento/freebsd-14"
    fw.vm.hostname = nil
    fw.ssh.shell = "sh"
    fw.vm.boot_timeout = 900
    vm_resources(fw, "fw", conf("FW_MEMORY", "1536").to_i, conf("FW_CPUS", "2").to_i)

    # NIC 2-4 are plugged in directly: their IPs (.1 on every segment) are set
    # by OPNsense from config.xml, Vagrant must not touch them.
    fw.vm.provider "virtualbox" do |vb|
      { 2 => "minisoc-soc", 3 => "minisoc-servers", 4 => "minisoc-red" }.each do |nic, net|
        vb.customize ["modifyvm", :id, "--nic#{nic}", "intnet", "--intnet#{nic}", net,
                      "--nictype#{nic}", "virtio", "--cableconnected#{nic}", "on"]
      end
    end
    fw.vm.network "forwarded_port", guest: 443, host: conf("PORT_OPNSENSE", "8443").to_i, host_ip: "127.0.0.1", id: "opnsense-gui"

    fw.vm.provision "config", type: "file", source: "#{ROOT}/provision/firewall/config.xml.tpl", destination: "/tmp/config.xml.tpl"
    fw.vm.provision "bootstrap", type: "shell", path: "#{ROOT}/provision/firewall/bootstrap.sh",
      env: PROVISION_ENV, reboot: true
    fw.vm.provision "configure", type: "shell", path: "#{ROOT}/provision/firewall/configure.sh",
      env: PROVISION_ENV
  end

  # --------------------------------------------------------------------------
  # wazuh - SIEM / XDR (indexer + manager + dashboard, all-in-one)
  # --------------------------------------------------------------------------
  config.vm.define "wazuh" do |w|
    w.vm.box = "bento/ubuntu-24.04"
    w.vm.hostname = "wazuh"
    vm_resources(w, "wazuh", conf("WAZUH_MEMORY", "6144").to_i, conf("WAZUH_CPUS", "2").to_i)
    w.vm.network "private_network", ip: "10.10.10.10", virtualbox__intnet: "minisoc-soc"
    w.vm.network "forwarded_port", guest: 443, host: conf("PORT_WAZUH", "8444").to_i, host_ip: "127.0.0.1", id: "wazuh-dashboard"
    linux_base(w, "10.10.10.10", "10.10.10.1")
    w.vm.provision "wazuh-files", type: "file", source: "#{ROOT}/provision/wazuh", destination: "/tmp/minisoc-wazuh"
    w.vm.provision "wazuh", type: "shell", path: "#{ROOT}/provision/wazuh/install.sh", env: PROVISION_ENV
  end

  # --------------------------------------------------------------------------
  # soc - analyst tools: Greenbone (vulnerability scanning) + DFIR-IRIS (cases)
  # --------------------------------------------------------------------------
  if enabled?("soc")
    config.vm.define "soc" do |s|
      s.vm.box = "bento/ubuntu-24.04"
      s.vm.hostname = "soc"
      vm_resources(s, "soc", conf("SOC_MEMORY", "6144").to_i, conf("SOC_CPUS", "2").to_i)
      s.vm.network "private_network", ip: "10.10.10.20", virtualbox__intnet: "minisoc-soc"
      s.vm.network "forwarded_port", guest: 443,  host: conf("PORT_IRIS", "8445").to_i,      host_ip: "127.0.0.1", id: "iris"
      s.vm.network "forwarded_port", guest: 9392, host: conf("PORT_GREENBONE", "9392").to_i, host_ip: "127.0.0.1", id: "greenbone"
      linux_base(s, "10.10.10.20", "10.10.10.1")
      s.vm.provision "soc-files", type: "file", source: "#{ROOT}/provision/soc", destination: "/tmp/minisoc-soc"
      s.vm.provision "soc", type: "shell", path: "#{ROOT}/provision/soc/install.sh", env: PROVISION_ENV
    end
  end

  # --------------------------------------------------------------------------
  # sensor - Suricata IDS, listens silently on the SERVERS network
  # --------------------------------------------------------------------------
  if enabled?("sensor")
    config.vm.define "sensor" do |n|
      n.vm.box = "bento/ubuntu-24.04"
      n.vm.hostname = "sensor"
      vm_resources(n, "sensor", conf("SENSOR_MEMORY", "2048").to_i, conf("SENSOR_CPUS", "1").to_i)
      n.vm.network "private_network", ip: "10.10.10.30", virtualbox__intnet: "minisoc-soc"
      # Monitoring port: no IP address, promiscuous, sees all SERVERS traffic.
      n.vm.network "private_network", ip: "10.10.20.250", virtualbox__intnet: "minisoc-servers",
        auto_config: false, mac: "0800275E0001"
      n.vm.provider "virtualbox" do |vb|
        vb.customize ["modifyvm", :id, "--nicpromisc3", "allow-all"]
      end
      linux_base(n, "10.10.10.30", "10.10.10.1")
      n.vm.provision "sensor-files", type: "file", source: "#{ROOT}/provision/sensor", destination: "/tmp/minisoc-sensor"
      n.vm.provision "sensor", type: "shell", path: "#{ROOT}/provision/sensor/install.sh",
        env: PROVISION_ENV.merge("SNIFF_MAC" => "08:00:27:5e:00:01")
    end
  end

  # --------------------------------------------------------------------------
  # target - deliberately vulnerable Linux server (the victim)
  # --------------------------------------------------------------------------
  if enabled?("target")
    config.vm.define "target" do |t|
      t.vm.box = "bento/ubuntu-24.04"
      t.vm.hostname = "target"
      vm_resources(t, "target", conf("TARGET_MEMORY", "1536").to_i, conf("TARGET_CPUS", "1").to_i)
      t.vm.network "private_network", ip: "10.10.20.10", virtualbox__intnet: "minisoc-servers"
      # So you can browse the hidden portal app by hand from your own machine,
      # not just attack it from kali - same localhost-only pattern as the
      # other tools (see README's "Network isolation & safety").
      t.vm.network "forwarded_port", guest: 80, host: conf("PORT_TARGET", "8446").to_i, host_ip: "127.0.0.1", id: "target-web"
      linux_base(t, "10.10.20.10", "10.10.20.1")
      t.vm.provision "target-files", type: "file", source: "#{ROOT}/provision/target", destination: "/tmp/minisoc-target"
      t.vm.provision "target", type: "shell", path: "#{ROOT}/provision/target/install.sh", env: PROVISION_ENV
    end
  end

  # --------------------------------------------------------------------------
  # kali - the attacker (red team)
  # --------------------------------------------------------------------------
  if enabled?("kali")
    config.vm.define "kali" do |k|
      k.vm.box = "kalilinux/rolling"
      k.vm.hostname = "kali"
      vm_resources(k, "kali", conf("KALI_MEMORY", "2048").to_i, conf("KALI_CPUS", "2").to_i)
      k.vm.network "private_network", ip: "10.10.66.10", virtualbox__intnet: "minisoc-red"
      k.vm.provider "virtualbox" do |vb|
        vb.gui = conf("KALI_GUI", "false") == "true"
        vb.customize ["modifyvm", :id, "--vram", "64"]
      end
      linux_base(k, "10.10.66.10", "10.10.66.1")
      k.vm.provision "kali-files", type: "file", source: "#{ROOT}/provision/kali", destination: "/tmp/minisoc-kali"
      k.vm.provision "kali", type: "shell", path: "#{ROOT}/provision/kali/install.sh", env: PROVISION_ENV
    end
  end
end
