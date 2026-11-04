# API connection and free, open-source direction

Date: 4 November 2026
Status: Proposed implementation design; API-key direction and free/open-source product model selected by the owner.

## Connection flow

Replace the account sheet's browser experiment with a native connection form. Users supply a restricted IAM application's secret API key and their organization ID. Include a link to Scaleway's key-creation instructions. Use the existing SwiftUI styling and platform networking; no backend or new dependencies.

Keep the key on the device in Keychain, available only when unlocked and excluded from device migration. Never put secrets in logs, analytics, preferences, repository files, or error messages. Send credentials only to the fixed Scaleway API origin over HTTPS; reject redirects. Clear the key input after connection. Disconnect deletes the local credential and cached account data; explain that revocation is performed in Scaleway's console.

Use the secret key as the X-Auth-Token request header, as documented by Scaleway. Validate access through the reads actually needed by the app rather than treating key syntax or an unrelated IAM permission as proof of access.

## First useful version

Read current-month consumption and list existing Instances, with explicit zone selection and pagination. Determine the exact read-only permission sets from current documentation during implementation. Support separate errors for invalid/revoked credentials, missing permissions, and network failures. A spending-permission error must not hide successfully loaded Instances.

Keep sample data behind an explicit demo mode. Never substitute sample amounts for failed live reads. Label consumption as estimated and show currency, period, and refresh time. Do not aggregate different currencies. Disable demo start/stop/restart controls for live resources in this increment; live management is a separate change requiring write permissions.

## Approaches

- Selected: user-created restricted API key, direct device-to-Scaleway requests. Uses documented API authentication and avoids operating a credential-holding service.
- Parked: reverse-engineered console login. Unsupported, susceptible to breaking changes, and unsuitable for the desired passkey/SSO flow based on Scaleway's response.
- Backend-mediated access is unnecessary for this version and would introduce hosting and credential custody.

## Free and open source

All app functionality will be free. No IAP, subscriptions, or paid feature tiers. The owner selected MPL 2.0; the full licence is in the repository’s LICENSE file. Maintain contributor/build guidance and the unofficial-client notice before publishing. Review the repository for secrets and personal signing/device metadata before any public push. Public source repository: https://github.com/MoatCast/scaleway-companion.

## Acceptance

Verify request authentication, redirect rejection, credential removal, pagination, partial permission failures, and exact monetary decoding with focused tests. Perform a real read-only connection on a physical iPhone with a user-provided restricted key. Never request secrets in chat. Simulator testing is unnecessary for the first live verification.

## References

- https://www.scaleway.com/en/developers/api — X-Auth-Token authentication
- https://www.scaleway.com/en/developers/api/instance — zonal Instance reads
- https://www.scaleway.com/en/developers/api/billing — consumption and organization context
- Scaleway Slack response supplied by the owner on 2 November 2026
