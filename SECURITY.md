# Security

## Supported scope

This prototype has no stable release or security support guarantee. Security fixes target the latest `main` branch. Browser authentication is unsupported by Scaleway for third-party clients and may change without notice.

## Report privately

Use [Report a vulnerability](https://github.com/MoatCast/scaleway-companion/security/advisories/new). Do not open a public issue containing an exploitable vulnerability or credentials.

Describe affected code, reproduction steps, impact and any proposed fix. Use a disposable account and fictional or redacted data. Never include API keys, session/renewal tokens, credential-bearing callback URLs or sensitive account information. Do not access another person's account or change cloud resources without permission. Reports are reviewed as maintainer time allows; there is no guaranteed response deadline or bounty programme.

If a real key is exposed, revoke it in Scaleway immediately. Deleting a public comment or commit does not make an exposed credential safe again.

## Credential boundaries

Long-lived application keys belong in device-only Keychain. Temporary browser sessions remain in memory. Automated tests and workflows must not require live credentials. Authentication requests refuse redirects; automatic provisioning must preserve exact approved scopes and the existing connection until a verified replacement is saved. See [the setup documentation](docs/automatic-setup.md) for recovery and known limitations.
