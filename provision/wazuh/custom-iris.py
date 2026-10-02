#!/usr/bin/env python3
"""Wazuh -> DFIR-IRIS integration.

Wazuh's integrator daemon calls this script for every alert at or above the
level configured in ossec.conf (<integration><name>custom-iris</name>...).
It turns the Wazuh alert into an IRIS *alert*, with the attacker IP as an IOC
and the affected machine as an asset, so an analyst can triage it in IRIS and
escalate it into a case.

Called as:  custom-iris <alert_file> <api_key> <hook_url>
Log file:   /var/ossec/logs/integrations.log
"""
import datetime
import json
import ssl
import sys
import urllib.request

LOG_FILE = "/var/ossec/logs/integrations.log"

# IRIS severity ids (see IRIS: Manage > Severities)
SEV_INFORMATIONAL, SEV_LOW, SEV_MEDIUM, SEV_HIGH, SEV_CRITICAL = 2, 3, 4, 5, 6
ALERT_STATUS_NEW = 2
DEFAULT_CUSTOMER_ID = 1
TLP_AMBER = 2

# The lab uses IRIS's self-signed certificate.
TLS = ssl._create_unverified_context()


def log(msg):
    with open(LOG_FILE, "a") as f:
        f.write(f"{datetime.datetime.now():%Y/%m/%d %H:%M:%S} custom-iris: {msg}\n")


def iris_severity(level):
    if level >= 13:
        return SEV_CRITICAL
    if level >= 10:
        return SEV_HIGH
    if level >= 7:
        return SEV_MEDIUM
    if level >= 4:
        return SEV_LOW
    return SEV_INFORMATIONAL


def iris_request(base_url, api_key, path, payload=None):
    req = urllib.request.Request(
        base_url + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET",
    )
    with urllib.request.urlopen(req, context=TLS, timeout=15) as resp:
        return json.load(resp)


def lookup_id(base_url, api_key, path, name_field, id_field, wanted):
    """Find e.g. the id of IOC type 'ip-src'. Returns None if not found."""
    try:
        for item in iris_request(base_url, api_key, path).get("data", []):
            if item.get(name_field) == wanted:
                return item.get(id_field)
    except Exception as e:  # lookups are optional - the alert still gets sent
        log(f"lookup {path} failed: {e}")
    return None


def source_ip(alert):
    data = alert.get("data", {})
    return data.get("srcip") or data.get("src_ip") or data.get("srcIp")


def to_iso(timestamp):
    # Wazuh: 2026-10-02T10:12:09.123+0200
    try:
        return datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S.%f%z").isoformat()
    except (TypeError, ValueError):
        return datetime.datetime.now(datetime.timezone.utc).isoformat()


def build_alert(alert, base_url, api_key):
    rule = alert.get("rule", {})
    agent = alert.get("agent", {})
    level = int(rule.get("level", 0))
    src = source_ip(alert)

    description = [
        f"**Rule:** {rule.get('id')} (level {level}) - {rule.get('description')}",
        f"**Agent:** {agent.get('name')} ({agent.get('ip', 'n/a')})",
        f"**Source IP:** {src or 'n/a'}",
        f"**Groups:** {', '.join(rule.get('groups', []))}",
    ]
    mitre = rule.get("mitre", {})
    if mitre:
        description.append(f"**MITRE ATT&CK:** {', '.join(mitre.get('id', []))} "
                           f"({', '.join(mitre.get('technique', []))})")
    if alert.get("full_log"):
        description.append(f"\n```\n{alert['full_log'][:2000]}\n```")

    tags = ["wazuh", f"rule:{rule.get('id')}", f"agent:{agent.get('name')}"]
    tags += [f"mitre:{t}" for t in mitre.get("id", [])]

    payload = {
        "alert_title": f"{rule.get('description', 'Wazuh alert')}"[:240],
        "alert_description": "\n".join(description),
        "alert_source": "Wazuh",
        "alert_source_ref": alert.get("id", ""),
        "alert_source_link": "https://localhost:8444/app/threat-hunting",
        "alert_severity_id": iris_severity(level),
        "alert_status_id": ALERT_STATUS_NEW,
        "alert_source_event_time": to_iso(alert.get("timestamp")),
        "alert_note": "",
        "alert_tags": ",".join(tags),
        "alert_customer_id": DEFAULT_CUSTOMER_ID,
        "alert_source_content": alert,
        "alert_context": {
            "rule_id": rule.get("id"),
            "rule_level": level,
            "agent_name": agent.get("name"),
            "agent_ip": agent.get("ip"),
            "src_ip": src,
        },
    }

    if src:
        ioc_type = lookup_id(base_url, api_key, "/manage/ioc-types/list", "type_name", "type_id", "ip-src")
        if ioc_type:
            payload["alert_iocs"] = [{
                "ioc_value": src,
                "ioc_type_id": ioc_type,
                "ioc_tlp_id": TLP_AMBER,
                "ioc_description": "Source IP reported by Wazuh",
                "ioc_tags": "wazuh",
            }]

    if agent.get("name"):
        asset_type = lookup_id(base_url, api_key, "/manage/asset-type/list", "asset_name", "asset_id", "Linux - Server")
        if asset_type:
            payload["alert_assets"] = [{
                "asset_name": agent["name"],
                "asset_ip": agent.get("ip", ""),
                "asset_type_id": asset_type,
                "asset_description": "Wazuh agent",
            }]
    return payload


def main(argv):
    if len(argv) < 4:
        log(f"wrong arguments: {argv}")
        sys.exit(2)
    alert_file, api_key, hook_url = argv[1], argv[2], argv[3]
    base_url = hook_url.split("/alerts/add")[0]

    with open(alert_file) as f:
        alert = json.load(f)

    payload = build_alert(alert, base_url, api_key)
    try:
        result = iris_request(base_url, api_key, "/alerts/add", payload)
        if result.get("status") != "success":
            log(f"IRIS refused alert {alert.get('id')}: {result.get('message')} {result.get('data')}")
            sys.exit(1)
        log(f"sent alert {alert.get('id')} rule {alert['rule']['id']} -> IRIS alert #{result['data'].get('alert_id')}")
    except Exception as e:
        log(f"could not reach IRIS at {hook_url}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv)
