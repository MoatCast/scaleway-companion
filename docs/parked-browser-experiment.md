# Parked browser-login experiment

Historical custom-scheme implementation only. The current development-only localhost experiment is documented in [browser-sign-in-experiment.md](browser-sign-in-experiment.md).

Historical notes from the initial prototype. This flow is not exposed in the app. API-key connection replaced it on 4 November 2026.

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
