#!/usr/bin/env python3
"""Read-only checks for Nextshot feedback launch dependencies.

Credentials stay in memory. This command never changes Cloudflare settings.
"""

import argparse
import concurrent.futures
import json
import subprocess
import sys
import urllib.error
import urllib.request

ACCOUNT = "2afca1b8aab7ec4024bdb7cb2fec47c0"
ZONE = "ecc8cb0c8feb5e3a066062f76dfdbd49"
DESTINATION = "drewschulz1@gmail.com"
CHECKS = {
    "containers": f"/accounts/{ACCOUNT}/containers/applications",
    "queues": f"/accounts/{ACCOUNT}/queues",
    "r2": f"/accounts/{ACCOUNT}/r2/buckets",
    "d1": f"/accounts/{ACCOUNT}/d1/database",
    "access": f"/accounts/{ACCOUNT}/access/apps",
    "email_destinations": f"/accounts/{ACCOUNT}/email/routing/addresses",
    "email_routing_rules": f"/zones/{ZONE}/email/routing/rules",
    "billing": f"/accounts/{ACCOUNT}/subscriptions",
}


def inspect(name, path, token):
    request = urllib.request.Request(
        "https://api.cloudflare.com/client/v4" + path,
        headers={"Authorization": "Bearer " + token},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.load(response)
        if not data.get("success"):
            return {"check": name, "ok": False, "detail": "API check failed"}
        result = data.get("result")
        detail = "API access confirmed"
        if name == "email_destinations":
            verified = any(
                item.get("email", "").lower() == DESTINATION
                and bool(item.get("verified"))
                for item in result or []
            )
            return {
                "check": name,
                "ok": verified,
                "detail": "Destination verified" if verified else "Destination verification required",
            }
        if name == "billing":
            # A readable subscription list does not prove the required plan.
            detail = "Billing API readable; confirm Workers Paid in the account"
        return {"check": name, "ok": True, "detail": detail}
    except urllib.error.HTTPError as error:
        return {"check": name, "ok": False, "detail": f"HTTP {error.code}"}
    except (urllib.error.URLError, TimeoutError, ValueError):
        return {"check": name, "ok": False, "detail": "Connection or response check failed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", default="CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK")
    arguments = parser.parse_args()
    credential = subprocess.run(
        ["security", "find-generic-password", "-s", arguments.service, "-w"],
        capture_output=True,
        text=True,
        check=False,
    )
    token = credential.stdout.strip()
    if credential.returncode or not token:
        print(json.dumps({"ready": False, "credential": arguments.service, "detail": "Keychain credential unavailable"}))
        return 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(inspect, name, path, token) for name, path in CHECKS.items()]
        results = [future.result() for future in futures]
    print(json.dumps({
        "apiChecksPass": all(result["ok"] for result in results),
        "credentialLength": len(token),
        "checks": results,
        "launchReady": False,
        "remaining": "Verify deployed scanner engines, model artifacts, isolation, owner access, inbound MX and routing activation, cost controls, and synthetic delivery separately.",
    }, indent=2))
    return 0 if all(result["ok"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
