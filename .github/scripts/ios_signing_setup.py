#!/usr/bin/env python3
"""Distribution signing for the iOS Example, made once on Apple's side and kept as GitHub secrets.

Run by .github/workflows/ios-signing-setup.yml. With the App Store Connect API key it makes an Apple Distribution
certificate (the private key is made here and never leaves the run except inside the p12) and an App Store profile
for the app and for its Notification Service Extension, then writes them to this repository's Actions secrets for
.github/workflows/ios-testflight.yml. No device is needed: App Store profiles carry no device list.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, GH_SECRETS_TOKEN, GITHUB_REPOSITORY, RUNNER_TEMP, REVOKE_OLD,
APP_BUNDLE_ID, NSE_BUNDLE_ID, APP_PROFILE_NAME, NSE_PROFILE_NAME.
"""
import base64
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from nacl import encoding, public

ASC = "https://api.appstoreconnect.apple.com/v1"
GITHUB = "https://api.github.com"


class Failure(Exception):
    pass


def env(name):
    value = os.environ.get(name, "")
    if not value:
        raise Failure(f"{name} is not set.")
    return value


def request(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={**headers, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            parsed = json.loads(detail)
            if "errors" in parsed:
                detail = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ") for e in parsed["errors"])
            elif "message" in parsed:
                detail = parsed["message"]
        except ValueError:
            pass
        raise Failure(f"{method} {url.split('?')[0]}: HTTP {error.code}: {detail}") from None


class AppStoreConnect:
    def __init__(self, key_id, issuer_id, key_pem):
        now = int(time.time())
        token = jwt.encode(
            {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
            key_pem,
            algorithm="ES256",
            headers={"kid": key_id},
        )
        print(f"::add-mask::{token}")
        self.headers = {"Authorization": f"Bearer {token}"}

    def call(self, method, path, body=None, **query):
        url = ASC + path + ("?" + urllib.parse.urlencode(query) if query else "")
        return request(method, url, self.headers, body)


def openssl(*args, extra_env=None):
    result = subprocess.run(["openssl", *args], capture_output=True, text=True, env={**os.environ, **(extra_env or {})})
    if result.returncode != 0:
        raise Failure(f"openssl {args[0]} failed: {result.stderr.strip()}")


def bundle_id(asc, identifier, needs_push):
    found = asc.call("GET", "/bundleIds", **{"filter[identifier]": identifier, "include": "bundleIdCapabilities",
                                            "limit": 200})
    # The filter also matches longer identifiers (ai.clomni.example finds the extension too).
    match = [b for b in found["data"] if b["attributes"]["identifier"] == identifier]
    if not match:
        raise Failure(f"App ID {identifier} does not exist. Register it first: developer.apple.com → Certificates, "
                      "IDs & Profiles → Identifiers (ios/Example/README.md, TestFlight).")
    record = match[0]
    if needs_push:
        ids = {c["id"] for c in record.get("relationships", {}).get("bundleIdCapabilities", {}).get("data", [])}
        types = {c["attributes"]["capabilityType"] for c in found.get("included", []) if c["id"] in ids}
        if "PUSH_NOTIFICATIONS" not in types:
            raise Failure(f"App ID {identifier} has no Push Notifications capability; enable it under Identifiers, "
                          "then run this workflow again.")
    print(f"App ID {identifier}: {record['id']}")
    return record["id"]


def distribution_certificates(asc):
    found = asc.call("GET", "/certificates", **{"filter[certificateType]": "DISTRIBUTION", "limit": 200})
    return found["data"]


def describe(cert):
    a = cert["attributes"]
    return f"{cert['id']} ({a.get('displayName') or a.get('name')}, serial {a.get('serialNumber')}, " \
           f"expires {a.get('expirationDate')})"


def revoke_old(asc):
    old = distribution_certificates(asc)
    if not old:
        print("No Apple Distribution certificates to revoke.")
    for cert in old:
        asc.call("DELETE", f"/certificates/{cert['id']}")
        print(f"Revoked {describe(cert)}")


def create_certificate(asc, workdir):
    key = os.path.join(workdir, "dist.key")
    csr = os.path.join(workdir, "dist.csr")
    openssl("req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", csr,
            "-subj", "/CN=Clomni Example Distribution")
    with open(csr) as f:
        csr_pem = f.read()
    try:
        created = asc.call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})
    except Failure as error:
        existing = "\n".join("  " + describe(c) for c in distribution_certificates(asc)) or "  none"
        raise Failure(f"{error}\nApple Distribution certificates now:\n{existing}\nIf the limit is reached, run "
                      "again with revoke_old=true (it revokes every one listed).") from None
    cert = created["data"]
    der = os.path.join(workdir, "dist.cer")
    with open(der, "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
    pem = os.path.join(workdir, "dist.pem")
    openssl("x509", "-inform", "DER", "-in", der, "-out", pem)
    print(f"Certificate {describe(cert)}")
    return cert, key, pem


def create_profile(asc, name, bundle_record_id, cert_id):
    # Profile names are unique per team: the one from an earlier run is replaced.
    for old in asc.call("GET", "/profiles", **{"filter[name]": name, "limit": 200})["data"]:
        if old["attributes"]["name"] == name:
            asc.call("DELETE", f"/profiles/{old['id']}")
            print(f"Deleted the earlier profile \"{name}\" ({old['attributes'].get('uuid')})")
    created = asc.call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_record_id}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        },
    }})["data"]["attributes"]
    print(f"Profile \"{name}\": {created['uuid']}, expires {created['expirationDate']}")
    return created


class GitHubSecrets:
    def __init__(self, token, repository):
        self.headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"}
        self.base = f"{GITHUB}/repos/{repository}/actions/secrets"
        try:
            key = request("GET", f"{self.base}/public-key", self.headers)
        except Failure as error:
            raise Failure(f"{error}\nGH_SECRETS_TOKEN must be a fine-grained token for {repository} with "
                          "Secrets: write.") from None
        self.key_id = key["key_id"]
        self.box = public.SealedBox(public.PublicKey(key["key"].encode(), encoding.Base64Encoder()))

    def put(self, name, value):
        sealed = base64.b64encode(self.box.encrypt(value.encode())).decode()
        request("PUT", f"{self.base}/{name}", self.headers, {"encrypted_value": sealed, "key_id": self.key_id})
        print(f"Secret {name} written")


def main():
    workdir = os.path.join(env("RUNNER_TEMP"), "ios-signing")
    os.makedirs(workdir, mode=0o700, exist_ok=True)
    try:
        p12_password = secrets.token_urlsafe(24)
        print(f"::add-mask::{p12_password}")
        key_pem = env("ASC_KEY_P8").replace("\r", "").lstrip("﻿").strip() + "\n"
        if "-----BEGIN PRIVATE KEY-----" not in key_pem:
            raise Failure("ASC_KEY_P8 is not the text of an AuthKey_<id>.p8 file.")

        # Both sides are checked before anything is made on Apple's.
        github = GitHubSecrets(env("GH_SECRETS_TOKEN"), env("GITHUB_REPOSITORY"))
        asc = AppStoreConnect(env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), key_pem)
        app_bundle = bundle_id(asc, env("APP_BUNDLE_ID"), needs_push=True)
        nse_bundle = bundle_id(asc, env("NSE_BUNDLE_ID"), needs_push=False)

        if os.environ.get("REVOKE_OLD") == "true":
            revoke_old(asc)
        cert, key, pem = create_certificate(asc, workdir)
        app_profile = create_profile(asc, env("APP_PROFILE_NAME"), app_bundle, cert["id"])
        nse_profile = create_profile(asc, env("NSE_PROFILE_NAME"), nse_bundle, cert["id"])

        # -legacy: macOS's `security import` cannot read OpenSSL 3's default (AES/PBKDF2) PKCS#12.
        p12 = os.path.join(workdir, "dist.p12")
        openssl("pkcs12", "-export", "-legacy", "-inkey", key, "-in", pem, "-name", "Apple Distribution",
                "-passout", "env:P12_PASSWORD", "-out", p12, extra_env={"P12_PASSWORD": p12_password})
        with open(p12, "rb") as f:
            p12_base64 = base64.b64encode(f.read()).decode()

        github.put("IOS_DIST_P12", p12_base64)
        github.put("IOS_DIST_P12_PASSWORD", p12_password)
        github.put("IOS_PROFILE_APP", app_profile["profileContent"])
        github.put("IOS_PROFILE_NSE", nse_profile["profileContent"])
        github.put("IOS_PROFILE_APP_NAME", app_profile["name"])
        github.put("IOS_PROFILE_NSE_NAME", nse_profile["name"])

        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a") as f:
                f.write(f"Apple Distribution certificate {cert['id']}, expires "
                        f"{cert['attributes'].get('expirationDate')}.\n\n"
                        f"Profiles: \"{app_profile['name']}\" ({app_profile['uuid']}), "
                        f"\"{nse_profile['name']}\" ({nse_profile['uuid']}).\n\n"
                        "Secrets written; iOS TestFlight can run now.\n")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except Failure as failure:
        for line in str(failure).splitlines():
            print(f"::error::{line}")
        sys.exit(1)
