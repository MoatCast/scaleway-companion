# Browser sign-in experiment — 4 November 2026

Development builds only: connected Account → Browser sign-in experiment → Continue with Scaleway. The production connection remains the restricted API key. The user has confirmed that the existing live account data matches the console and survives relaunch.

## Boundaries

The experiment opens Scaleway’s actual authentication website through ASWebAuthenticationSession. It passes an ephemeral `http://localhost:<port>/<random UUID>/callback` through `redirectToUrl`. Network.framework requires the loopback interface, accepting IPv4/IPv6 locally without exposing a listener to Wi-Fi or cellular interfaces. The registered custom scheme is only a browser lifecycle sentinel and is never supplied to Scaleway as the redirect.

The listener accepts only GET requests with the exact attempt path, localhost Host and assigned port, a single base64 session envelope, no fragments or credentials, and bounded request/token sizes. Unrelated and malformed requests get generic rejection responses; they do not consume the legitimate handoff. The first valid callback closes the listener. Slow clients expire after five seconds; the attempt expires after three minutes. Cancellation/dismissal closes the receiver and pending connections. Browser dismissal after callback receipt cannot cancel the accepted handoff.

Only the session token and session identity metadata are decoded; renewal credentials are ignored. Nothing writes these tokens to Keychain, preferences, logs, screenshots or a backend. A no-store, no-referrer, plain-text callback response never echoes credentials. Token-bearing callback URLs must not be copied into debugging tools or captured in screenshots. The local app drops its in-memory envelope after the experiment; it does not revoke the provider session or sign out of Scaleway elsewhere.

The session’s jti, audience and expiry are checked through `GET /iam/v1alpha1/jwts/{jti}`. Two independent GETs then use `X-Session-Token` and the currently connected Organization ID:

- Instances: first page, one record, `fr-par-1`, organization filter.
- Consumption: first page, one record, current UTC billing month, organization filter.

Both APIs must return HTTP 200 and the expected typed JSON body. An empty list can verify endpoint access; the experiment does not establish access to all projects or zones. Redirects are refused. All errors shown in the app are sanitized. The existing dashboard, credential and billing calculations are untouched; no keys, policies or resources are created or changed.

## Results and manual procedure

The screen reports callback receipt, verified session/expiry, and each API result separately. Timeout, cancellation and failure are distinct. Because the app cannot inspect a system authentication browser’s page, a visible “Invalid app to redirect” error must be reported using the result screen’s button after closing the browser. Timeout alone is not evidence of redirect rejection.

1. Keep the connected iPhone unlocked. Open Account → Browser sign-in experiment.
2. Start with the existing passkey, using Scaleway’s webpage. Do not share credentials, callback URLs or browser screenshots.
3. Return to the app and inspect callback, session, Instances and consumption results. Success requires **all four**: accepted iPhone callback, verified session, verified Instances read, verified consumption read.
4. Return to Overview and refresh: confirm the saved API-key connection remains usable.
5. Repeat and cancel from the browser, then repeat and cancel from the app if available. Confirm the saved connection still works.
6. Password/MFA or SSO should only be attempted if already configured; record untested methods explicitly.

No approval prompt for restricted access is invented here: this unsupported console session may carry the signed-in user’s permissions. If the gate passes, a separate design must explain and request approval before provisioning a dedicated IAM application with InstancesReadOnly on selected projects and BillingReadOnly on the Organization. Never copy the CLI’s user-key creation, since keys inherit their bearer’s permissions. Manual API keys remain available when provisioning is not permitted.

## Evidence

- 41 macOS core checks pass, including actual localhost HTTP delivery, unrelated-request rejection, one-shot consumption, cancellation, timeout cleanup, browser-dismissal ordering, malformed callback/token rejection, verification identity/expiry, refused redirects and rejected/malformed API responses.
- Signed Debug iPhone build and generic unsigned Release build succeed. Corrected Debug build installed on the connected physical iPhone; automatic launch was blocked while it was locked. A simulator was not started.
- Independent static review found a suspension-boundary callback/dismissal race. Receipt is now recorded synchronously in the receiver and consulted by the browser-dismissal handler; regression checks and the full suite pass after the fix.
- **Owner-confirmed physical iPhone result, 4 November 2026:** existing-passkey sign-in completed; callback, session and both API reads were verified. This passes the experiment’s callback/session/API success gate. This is owner-reported device evidence, not an automated test or a provider support guarantee.
- Cancellation with the live account and continued saved-key access after successful/failed/cancelled attempts remain pending manual verification. Password/MFA and SSO are untested.

## Proposed onboarding after the successful handoff

The diagnostic experiment still creates nothing. The owner subsequently authorized the separate [automatic setup implementation](automatic-setup.md), which now uses this design.

1. After browser authentication, verify the session and identify available Organizations. Ask the user to choose an Organization and projects; do not silently reuse the experiment’s already-connected Organization for a new account.
2. Show a permission summary before any provisioning: a dedicated IAM application; InstancesReadOnly on selected projects; BillingReadOnly at Organization scope. Explain that BillingReadOnly covers more than consumption, including other billing information, and that the temporary console session may carry the user’s broader account permissions.
3. Offer an explicit **Create read-only connection** action plus Cancel and Use an existing API key. No application, key or policy is created until that action. Keep any currently saved connection active during setup.
4. Check whether the account can provision the requested access. If it cannot, explain the missing capability and offer the existing manual-key connection. Do not request broader permissions or create a user-bound API key as a fallback.
5. Create a dedicated application, the narrowly scoped policy and an application-bound key. Verify its read access with the existing API client, allowing for IAM propagation with bounded retries. Do not treat an empty list as evidence that every intended project is accessible; separately check the selected scopes.
6. Only after verification, save the new application key to device Keychain and switch the connection. Discard the temporary browser session from app memory. Cancellation or failure preserves the existing connection; track resources created during this attempt so cleanup can target only those resources and explain any cleanup failure without exposing secrets.
7. Keep local Disconnect distinct from revoking the application/key in Scaleway, and provide clear revocation guidance.

Acceptance for this later implementation must cover provisioning permissions, restricted scope, partial creation/cleanup, propagation timeouts and atomic replacement of the saved connection. The successful session-read experiment does not itself verify provisioning. Resource creation requires the separate setup screen’s explicit approval. Exact IAM request contracts must be checked against current provider documentation before implementation.

This remains an unsupported, CLI-style session handoff, not a registered OAuth/PKCE client or a production sign-in option. Scaleway may disable it or change it without notice.

References: [official CLI](https://github.com/scaleway/scaleway-cli/blob/main/internal/namespaces/login/login.go), [credential model](https://www.scaleway.com/en/docs/iam/credentials/create-api-keys/), [Apple listener port](https://developer.apple.com/documentation/network/nwlistener/port), [historical custom-scheme failure](parked-browser-experiment.md).
