#!/usr/bin/env python3
"""Wait for a newly uploaded App Store Connect build to finish processing.

Never print the API credential or entire API responses: build metadata alone is
written as release evidence. The signing key remains on the runner's temp disk.
"""
import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_signature_to_raw(der):
    # OpenSSL emits ASN.1 DER; JWS ES256 requires fixed-width R || S.
    def length(offset):
        first = der[offset]
        if first < 128:
            return first, offset + 1
        count = first & 0x7f
        if count == 0 or count > 2 or offset + 1 + count > len(der):
            raise ValueError("Invalid DER length")
        return int.from_bytes(der[offset + 1:offset + 1 + count], "big"), offset + 1 + count

    if not der or der[0] != 0x30:
        raise ValueError("Invalid DER signature")
    total, pos = length(1)
    if pos + total != len(der):
        raise ValueError("Invalid DER sequence size")
    values = []
    for _ in range(2):
        if pos >= len(der) or der[pos] != 0x02:
            raise ValueError("Invalid DER integer")
        size, pos = length(pos + 1)
        raw = der[pos:pos + size]
        pos += size
        number = int.from_bytes(raw, "big")
        if not raw or number >= 1 << 256:
            raise ValueError("Invalid ES256 scalar")
        values.append(number.to_bytes(32, "big"))
    if pos != len(der):
        raise ValueError("Trailing DER data")
    return b"".join(values)


def jwt(key_path, key_id, issuer_id):
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    encoded = ".".join(b64(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload))
    signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                            input=encoded.encode(), capture_output=True, check=True).stdout
    return encoded + "." + b64(der_signature_to_raw(signed))


def api(path, key_path, key_id, issuer_id, params=None):
    url = "https://api.appstoreconnect.apple.com/v1/" + path
    if params:
        url += "?" + urlencode(params)
    request = Request(url, headers={"Authorization": "Bearer " + jwt(key_path, key_id, issuer_id),
                                    "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)["data"]


def uploaded_after(attributes, started):
    uploaded = attributes.get("uploadedDate")
    if not uploaded:
        return False
    return datetime.fromisoformat(uploaded.replace("Z", "+00:00")) >= started


def select_build(builds, number, started):
    for build in builds:
        attrs = build["attributes"]
        if attrs.get("version") == number and uploaded_after(attrs, started):
            return build
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-path", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--started-at", required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--attempts", type=int, default=40)
    parser.add_argument("--interval", type=int, default=30)
    args = parser.parse_args()
    started = datetime.fromisoformat(args.started_at.replace("Z", "+00:00"))
    if started.tzinfo is None:
        parser.error("--started-at must include a timezone")
    if args.attempts < 1 or args.interval < 0:
        parser.error("Invalid polling bounds")
    apps = api("apps", args.key_path, args.key_id, args.issuer_id,
               {"filter[bundleId]": args.bundle_id, "limit": 10})
    matching = [app for app in apps if app["attributes"]["bundleId"] == args.bundle_id]
    if len(matching) != 1:
        raise RuntimeError("Expected exactly one registered app for bundle ID")
    app_id = matching[0]["id"]
    for attempt in range(args.attempts):
        builds = api("builds", args.key_path, args.key_id, args.issuer_id,
                     {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 100})
        build = select_build(builds, args.build_number, started)
        if build:
            attrs = build["attributes"]
            state = attrs.get("processingState")
            evidence = {"app_id": app_id, "bundle_id": args.bundle_id,
                        "build_id": build["id"], "build_number": args.build_number,
                        "uploaded_at": attrs.get("uploadedDate"), "processing_state": state,
                        "observed_at": datetime.now(timezone.utc).isoformat()}
            args.evidence.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
            print(f"ASC build {build['id']}: {state}", flush=True)
            if state == "VALID":
                return
            if state in ("INVALID", "FAILED"):
                raise RuntimeError("ASC processing failed; see build evidence")
        else:
            print("New upload not visible in ASC yet", flush=True)
        if attempt + 1 < args.attempts:
            time.sleep(args.interval)
    raise TimeoutError("No VALID processed build before polling deadline")


if __name__ == "__main__":
    main()
