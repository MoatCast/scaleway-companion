# Scaleway Companion — native prototype

An unofficial iPhone app prototype based on the approved Liquid Glass mockup. SwiftUI, iOS 26+, no third-party dependencies. **All dashboard values are sample data**, even after a successful login experiment.

## Product direction — 4 November 2026

The app will be fully free and open source, with no paid tiers, subscriptions, or in-app purchases. The source is licensed under the [Mozilla Public License 2.0](LICENSE). Public repository: [MoatCast/scaleway-companion](https://github.com/MoatCast/scaleway-companion).

API-key authentication is the chosen connection method. Password/TOTP reverse engineering, hosted credential login, passkeys, and SSO are parked. Scaleway's response supplied by the owner confirms that its console authentication is not intended for third-party use and may change without notice.

The next implementation is described in [the API connection design](docs/api-connection-design.md). It is not implemented yet. The browser experiment below remains historical prototype code, not the intended beta login flow.

## Open and run

Open `ScalewayCompanion.xcodeproj` in Xcode, select the **ScalewayCompanion** scheme and an iPhone simulator, then Run (⌘R).

Xcode is installed at `/Applications/Xcode.app`. The system's command-line selection currently points at Command Line Tools. This project can build without changing that selection:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ScalewayCompanion.xcodeproj -scheme ScalewayCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
```

For a physical iPhone, select your signing team in Signing & Capabilities and use a unique bundle identifier. No signing account has been configured by this prototype.

## Try the dashboard

- Overview shows sample October 2026 consumption (€42.80) and three Instances.
- Filter all three tabs by Production (€36.80) or Personal (€6.00).
- Open an Instance to inspect details and simulate start/stop/restart, with confirmation.
- Sample actions change memory only and reset when the app restarts.
- Native tab bars, toolbar controls and the project selector use Liquid Glass. System appearance and Dynamic Type are supported.

## Login experiment

Tap the account button at the top right, then **Continue with Scaleway**.

1. An ephemeral `ASWebAuthenticationSession` opens `https://account.scaleway.com/authenticate`.
2. The `redirectToUrl` parameter asks Scaleway to return to `scalewaycompanion://login/callback/<random-attempt-id>`.
3. If Scaleway accepts this mobile callback, the app checks the URL against the current attempt, decodes the CLI-style base64 token envelope, and rejects malformed or ambiguous input.
4. A single GET to `https://api.scaleway.com/iam/v1alpha1/jwts/{jti}` uses `X-Session-Token` to check API access. An HTTP 200 is required; the returned session ID, audience and expiry must also match.
5. The UI reports a verified session, cancellation, timeout or a sanitized failure. Tokens and renewal tokens are never persisted or logged. No API key is created. The dashboard remains in demo mode.

The experiment does **not** establish that Scaleway supports third-party mobile clients. The official CLI uses a localhost callback. Our custom-scheme callback was rejected in the physical-device test documented below. This does not establish that all mobile integrations are impossible. HTTPS callbacks would require an associated domain and Scaleway approval of the redirect hostname. This is a CLI-style token handoff, **not** a registered OAuth/PKCE integration; do not ship it as production authentication without resolving that support/security contract.

**Physical-device result, 1 November 2026:** The user reported “Invalid app to redirect” during real sign-in on the iPhone. Inspection of Scaleway's publicly served [authentication route](https://account.scaleway.com/assets/Authenticate-CdSeTey_.js), [redirect validator](https://account.scaleway.com/assets/common-BsiJprxe.js), and [production configuration](https://account.scaleway.com/assets/account-BUK1yo6N.js) found an allowed-hostname check before callback-token creation. The production allowlist contains `online.net`, `scaleway.com`, `scw.eu`, and `localhost`; the validator matches those domains or their subdomains. Our `scalewaycompanion://login/callback/<attempt>` URL has hostname `login` and fails this check. The current custom-scheme flow is therefore blocked, and moving it to an arbitrary HTTPS domain would not by itself resolve the rejection. No successful app callback or API verification has been established. These public implementation details are dated observations, not a third-party authentication contract. Next steps are to obtain Scaleway's supported integration/redirect requirements or use documented IAM API-key authentication for a separate beta connection flow. No simulator or device tests were run for this diagnosis.

The request to inspect a session can also fail because of IAM permissions. The app distinguishes receipt of a callback from successful API verification. The prototype has a three-minute attempt timeout, can be cancelled, rejects stale attempts, blocks API redirects and discards the token after verification. Clearing the result only clears local UI state; it does not revoke a server-side session or sign out other devices.

### Manual acceptance check

- Open the browser and verify that Scaleway's sign-in page loads.
- Enter credentials **only in that Scaleway browser page**, including MFA if requested.
- Record whether it returns to the app and whether the result says “Session verified”. Do not capture/share tokens or credential-bearing callback URLs.
- If Scaleway rejects or drops the callback, record the visible non-sensitive error. Ask Scaleway which iOS callback mechanism is supported for third-party clients.
- Cancel, retry, and dismiss the sheet during an attempt; no previous attempt should change the new result.

No real account login has been performed by the agent. No cloud resource actions, API-key creation, backend, persisted credentials, IAP or TestFlight upload are included.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ScalewayCompanion.xcodeproj -scheme ScalewayCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath .build test CODE_SIGNING_ALLOWED=NO
```

Unit tests cover callback correlation, malformed/duplicate/oversized tokens, header/path injection, session verification, redirect rejection and exact monetary reconciliation. UI tests exercise project filtering, tab navigation, confirmation/cancellation of demo actions and opening/cancelling the browser. Browser tests never enter credentials.

Verified on 1 November 2026 using the **Scaleway Prototype** iPhone 18 Pro simulator (iOS 27.2): all eight unit tests and three UI scenarios passed across the full run and focused dashboard rerun. Testing exposed an Instance-row hit-area issue, fixed with `contentShape(Rectangle())`. The dashboard test now dismisses native confirmation popovers by tapping the visible detail sheet and checks the detail status before and after the sample action. Results are in `.build/FullVerification-20261101.xcresult` (unit/account passes; original dashboard dismissal failure) and `.build/DashboardDismissalVerification.xcresult` (dashboard pass). The authentication browser opened and cancelled successfully, but its captured page content was blank; sign-in-page loading, real credentials, callback delivery and live API access remain unverified.

## References

- [Scaleway CLI browser login](https://www.scaleway.com/en/docs/scaleway-cli/quickstart/)
- [Official CLI implementation inspected](https://github.com/scaleway/scaleway-cli/blob/a9e0359ccfb26626b890035457230109b9d7aa4e/internal/namespaces/login/login.go)
- [Scaleway JWT inspection API](https://www.scaleway.com/en/developers/api/iam/jwts)
- [Apple custom-scheme authentication callback](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/customscheme(_:))
- [Apple Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

## Licence

This project’s original source code is licensed under the [Mozilla Public License 2.0](LICENSE) (SPDX: `MPL-2.0`). Contributions to covered source files are provided under the same licence. This is an independent, unofficial client and is not affiliated with or endorsed by Scaleway. Third-party names and trademarks remain the property of their respective owners.
