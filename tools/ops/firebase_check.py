#!/usr/bin/env python3
"""Checks the Firebase service account (GitHub secret) without printing it.

Env FIREBASE_SERVICE_ACCOUNT = the service-account JSON.
Writes the compact JSON to $OUT_JSON (for `supabase secrets set`) and prints
a Markdown report: project, Google sign-in of the account, and an FCM
"validate only" send to a dummy token. An INVALID_ARGUMENT answer to that
send means the credentials and the FCM API both work (the dummy token is
simply not a real phone).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT (with cryptography)


def say(line=''):
    print(line, flush=True)


def post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')


def main():
    raw = os.environ.get('FIREBASE_SERVICE_ACCOUNT', '').strip()
    if not raw:
        say('- FIREBASE_SERVICE_ACCOUNT GitHub secret: **missing**')
        return 2
    try:
        sa = json.loads(raw)
    except Exception:
        say('- ❌ FIREBASE_SERVICE_ACCOUNT is not valid JSON. Paste the whole downloaded file, including the outer `{ }`.')
        return 1
    missing = [k for k in ('type', 'project_id', 'private_key', 'client_email', 'token_uri') if not sa.get(k)]
    if sa.get('type') != 'service_account' or missing:
        say(f"- ❌ That JSON is not a service-account key (type={sa.get('type')!r}, missing {missing}). "
            'Use Project settings → Service accounts → Generate new private key. '
            '(google-services.json goes in the other secret.)')
        return 1
    project = sa['project_id']
    email = sa['client_email']
    say(f'- project: `{project}`')
    say(f"- service account: `…@{email.split('@')[-1]}`")
    with open(os.environ.get('OUT_JSON', 'sa.json'), 'w') as f:
        f.write(json.dumps(sa, separators=(',', ':')))

    now = int(time.time())
    assertion = jwt.encode({
        'iss': email, 'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud': sa['token_uri'], 'iat': now, 'exp': now + 600,
    }, sa['private_key'], algorithm='RS256')
    status, body = post(sa['token_uri'], urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': assertion,
    }).encode(), {'Content-Type': 'application/x-www-form-urlencoded'})
    if status != 200:
        say(f'- ❌ Google sign-in with the key failed (HTTP {status}): `{body[:200]}`')
        return 1
    token = json.loads(body)['access_token']
    say('- Google sign-in with the key ✅')

    status, body = post(
        f'https://fcm.googleapis.com/v1/projects/{project}/messages:send',
        json.dumps({'validate_only': True, 'message': {
            'token': 'booknest-ci-dummy-token', 'data': {'title': 'test', 'body': 'test'}}}).encode(),
        {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    try:
        err = json.loads(body).get('error', {})
    except Exception:
        err = {}
    reason = err.get('status', '')
    if status == 200 or reason == 'INVALID_ARGUMENT':
        say('- FCM API test send ✅ (credentials accepted; dummy token rejected as expected)')
        return 0
    if status in (401, 403):
        say(f'- ❌ FCM refused the key (HTTP {status} {reason}). In Google Cloud → APIs, enable '
            '"Firebase Cloud Messaging API" for this project.')
        return 1
    say(f'- ⚠️ FCM answered HTTP {status} {reason}: `{err.get("message", body)[:200]}`')
    return 1


if __name__ == '__main__':
    sys.exit(main())
