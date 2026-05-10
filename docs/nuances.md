# Integration Nuances

Deviations from upstream docs discovered in practice.

## oCIS ↔ Authelia OIDC — Android app `token_endpoint_auth_method`

Guide: [Authelia docs → ownCloud Infinite Scale integration](https://www.authelia.com/integration/openid-connect/clients/ocis/)
Versions: Authelia `v4.39.16`, oCIS `v8.0.1`, ownCloud Android app (2026-04).

The guide specifies `token_endpoint_auth_method: 'client_secret_basic'` for the
Android client. In practice the app sends credentials via POST body, so Authelia
rejects the token exchange with `invalid_client` (method mismatch). Use
`client_secret_post` instead for the Android client block:

```yaml
- client_id: 'e4rAsNUSIUs0lF4nbv9FmCeUkTlV9GdgTLDH1b5uie7syb90SzEVrbN7HIpmWJeD'
  client_name: 'ownCloud Infinite Scale (Android)'
  client_secret: 'dInFYGV33xKzhbRmpqQltYNdfLdJIfJ9L5ISoKhNoT9qZftpdWSP71VrpGR9pmoD'
  public: false
  authorization_policy: 'two_factor'
  require_pkce: true
  pkce_challenge_method: 'S256'
  redirect_uris:
    - 'oc://android.owncloud.com'
  scopes:
    - 'openid'
    - 'offline_access'
    - 'groups'
    - 'profile'
    - 'email'
  response_types:
    - 'code'
  grant_types:
    - 'authorization_code'
    - 'refresh_token'
  access_token_signed_response_alg: 'none'
  userinfo_signed_response_alg: 'none'
  token_endpoint_auth_method: 'client_secret_post'  # deviates from guide
```

## oCIS app passwords — CLI requires explicit registry env

oCIS 8.0.x has no web UI for app tokens (rclone, mobile clients). Tokens are
managed via CLI or REST API only — see upstream `services/auth-app/README.md`.

The running oCIS process uses the embedded NATS service registry. A fresh
`ocis` CLI subprocess started via `podman exec` defaults to `mdns` and fails
with `com.owncloud.api.gateway: service not found`. Override on the exec:

```bash
sudo podman exec \
  -e MICRO_REGISTRY=nats-js-kv \
  -e MICRO_REGISTRY_ADDRESS=127.0.0.1:9233 \
  ocis ocis auth-app create --user-name=<user> --expiration=8760h
```

The token in the JSON output is the password — it's bcrypt-hashed at rest, so
copy it now. Use it as the password in any WebDAV client (rclone:
`rclone obscure '<token>'` then `pass = <obscured>`).

