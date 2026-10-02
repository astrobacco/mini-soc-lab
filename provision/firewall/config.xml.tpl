<?xml version="1.0"?>
<!--
  Mini-SOC OPNsense base configuration.

  This file is copied to /conf/config.xml BEFORE opnsense-bootstrap runs, so the
  firewall comes up already configured. Placeholders in double braces
  are filled in by provision/firewall/bootstrap.sh.

  Interface mapping (VirtualBox NIC -> FreeBSD -> OPNsense):
    NIC1  NAT       vtnet0  WAN      DHCP (10.0.2.15), internet + host port forwards
    NIC2  intnet    vtnet1  SOC      10.10.10.1/24   (OPNsense calls this "lan")
    NIC3  intnet    vtnet2  SERVERS  10.10.20.1/24   (opt1)
    NIC4  intnet    vtnet3  RED      10.10.66.1/24   (opt2)
-->
<opnsense>
  <theme>opnsense</theme>
  <system>
    <optimization>normal</optimization>
    <hostname>fw</hostname>
    <domain>minisoc.lab</domain>
    <dnsallowoverride>1</dnsallowoverride>
    <dnsallowoverride_exclude/>
    <group>
      <name>admins</name>
      <description>System Administrators</description>
      <scope>system</scope>
      <gid>1999</gid>
      <member>0</member>
      <member>2000</member>
      <priv>page-all</priv>
    </group>
    <user>
      <name>root</name>
      <descr>System Administrator</descr>
      <scope>system</scope>
      <groupname>admins</groupname>
      <!-- default "opnsense"; replaced with the lab password after first boot -->
      <password>$2y$10$YRVoF4SgskIsrXOvOQjGieB9XqHPRra9R7d80B3BZdbY/j21TwBfS</password>
      <uid>0</uid>
    </user>
    <user>
      <name>vagrant</name>
      <descr>Vagrant provisioning account (SSH key only)</descr>
      <scope>user</scope>
      <groupname>admins</groupname>
      <!-- "*" never matches a password: this account can only log in with its SSH key -->
      <password>*</password>
      <uid>2000</uid>
      <shell>/bin/sh</shell>
      <authorizedkeys>{{VAGRANT_AUTHORIZED_KEYS_B64}}</authorizedkeys>
    </user>
    <nextuid>2001</nextuid>
    <nextgid>2000</nextgid>
    <sudo_allow_wheel>2</sudo_allow_wheel>
    <timezone>Europe/Zurich</timezone>
    <timeservers>0.opnsense.pool.ntp.org 1.opnsense.pool.ntp.org</timeservers>
    <webgui>
      <protocol>https</protocol>
    </webgui>
    <disablenatreflection>yes</disablenatreflection>
    <usevirtualterminal>1</usevirtualterminal>
    <disableconsolemenu/>
    <bogons>
      <interval>monthly</interval>
    </bogons>
    <pf_share_forward>1</pf_share_forward>
    <lb_use_sticky>1</lb_use_sticky>
    <ssh>
      <group>admins</group>
      <enabled>enabled</enabled>
    </ssh>
    <rrdbackup>-1</rrdbackup>
    <netflowbackup>-1</netflowbackup>
  </system>
  <interfaces>
    <wan>
      <enable>1</enable>
      <descr>WAN</descr>
      <if>vtnet0</if>
      <ipaddr>dhcp</ipaddr>
      <!-- WAN sits behind VirtualBox NAT (10.0.2.0/24): private addresses must not be blocked -->
      <!-- (blockpriv / blockbogons deliberately absent: any present tag means "on") -->
    </wan>
    <lan>
      <enable>1</enable>
      <descr>SOC</descr>
      <if>vtnet1</if>
      <ipaddr>10.10.10.1</ipaddr>
      <subnet>24</subnet>
    </lan>
    <opt1>
      <enable>1</enable>
      <descr>SERVERS</descr>
      <if>vtnet2</if>
      <ipaddr>10.10.20.1</ipaddr>
      <subnet>24</subnet>
    </opt1>
    <opt2>
      <enable>1</enable>
      <descr>RED</descr>
      <if>vtnet3</if>
      <ipaddr>10.10.66.1</ipaddr>
      <subnet>24</subnet>
    </opt2>
  </interfaces>
  <unbound>
    <enable>1</enable>
  </unbound>
  <nat>
    <outbound>
      <mode>automatic</mode>
    </outbound>
  </nat>
  <filter>
    <!-- ===== WAN: only the VirtualBox host (10.0.2.2) may manage the firewall ===== -->
    <rule>
      <type>pass</type>
      <interface>wan</interface>
      <ipprotocol>inet</ipprotocol>
      <protocol>tcp</protocol>
      <source><address>10.0.2.2</address></source>
      <destination><network>(self)</network><port>22</port></destination>
      <descr>Host: SSH (vagrant)</descr>
    </rule>
    <rule>
      <type>pass</type>
      <interface>wan</interface>
      <ipprotocol>inet</ipprotocol>
      <protocol>tcp</protocol>
      <source><address>10.0.2.2</address></source>
      <destination><network>(self)</network><port>443</port></destination>
      <descr>Host: Web GUI</descr>
    </rule>

    <!-- ===== SOC: trusted management network ===== -->
    <rule>
      <type>pass</type>
      <interface>lan</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>lan</network></source>
      <destination><any/></destination>
      <descr>SOC: allow everything (trusted analysts and scanners)</descr>
    </rule>

    <!-- ===== SERVERS: victim network ===== -->
    <rule>
      <type>pass</type>
      <interface>opt1</interface>
      <ipprotocol>inet</ipprotocol>
      <protocol>tcp</protocol>
      <source><network>opt1</network></source>
      <destination><address>10.10.10.10</address><port>1514-1515</port></destination>
      <descr>SERVERS: Wazuh agents to manager</descr>
    </rule>
    <rule>
      <type>block</type>
      <interface>opt1</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt1</network></source>
      <destination><network>lan</network></destination>
      <log>1</log>
      <descr>SERVERS: block everything else into the SOC</descr>
    </rule>
    <rule>
      <type>block</type>
      <interface>opt1</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt1</network></source>
      <destination><network>(self)</network></destination>
      <log>1</log>
      <descr>SERVERS: no access to the firewall itself</descr>
    </rule>
    <rule>
      <type>pass</type>
      <interface>opt1</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt1</network></source>
      <destination><any/></destination>
      <log>1</log>
      <descr>SERVERS: outbound (internet, RED) - logged</descr>
    </rule>

    <!-- ===== RED: attacker network ===== -->
    <rule>
      <type>block</type>
      <interface>opt2</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt2</network></source>
      <destination><network>lan</network></destination>
      <log>1</log>
      <descr>RED: attackers never reach the SOC</descr>
    </rule>
    <rule>
      <type>block</type>
      <interface>opt2</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt2</network></source>
      <destination><network>(self)</network></destination>
      <log>1</log>
      <descr>RED: no access to the firewall itself</descr>
    </rule>
    <rule>
      <type>pass</type>
      <interface>opt2</interface>
      <ipprotocol>inet</ipprotocol>
      <source><network>opt2</network></source>
      <destination><any/></destination>
      <log>1</log>
      <descr>RED: attack the SERVERS / reach the internet - logged</descr>
    </rule>
  </filter>
  <OPNsense>
    <Syslog version="1.0.2">
      <general>
        <enabled>1</enabled>
        <loglocal>1</loglocal>
        <maxpreserve>31</maxpreserve>
        <maxfilesize/>
      </general>
      <destinations>
        <destination uuid="5d0c3b1e-6b1a-4f0e-9c1a-1a2b3c4d5e6f">
          <enabled>1</enabled>
          <transport>udp4</transport>
          <program/>
          <level/>
          <facility/>
          <hostname>10.10.10.10</hostname>
          <certificate/>
          <port>514</port>
          <rfc5424>0</rfc5424>
          <description>Wazuh manager</description>
        </destination>
      </destinations>
    </Syslog>
  </OPNsense>
  <rrd>
    <enable/>
  </rrd>
  <ntpd>
    <prefer>0.opnsense.pool.ntp.org</prefer>
  </ntpd>
</opnsense>
