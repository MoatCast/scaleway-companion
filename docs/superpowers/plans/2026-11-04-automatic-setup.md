# Automatic restricted connection setup implementation plan

> Execute inline using executing-plans and test-driven-development. The owner explicitly approved the existing onboarding design in docs/browser-sign-in-experiment.md.

**Goal:** Browser sign-in → select Organization/projects → approve restricted IAM application setup → verify and save application key → dashboard.
**Architecture:** Reuse the iPhone loopback/browser handoff. Add a fixed-origin IAM client and an in-memory setup coordinator with targeted rollback. Dashboard commits a verified key atomically, preserving the current connection until Keychain save succeeds.
**Tech Stack:** SwiftUI, Network, Foundation URLSession, Security Keychain. No dependencies or backend.
**Spec:** docs/browser-sign-in-experiment.md, Proposed onboarding after the successful handoff; current owner instruction supersedes its old no-provisioning implementation boundary.

## Global constraints

- No simulators. No credentials or authenticated browser screenshots/logging. Browser sessions remain memory-only.
- A user must press Create read-only connection after seeing scopes. Never create a user-bound key.
- InstancesReadOnly for explicitly selected project UUIDs; BillingReadOnly for the chosen Organization. No all-project wildcard, IAM privileges or extra permission sets on the new application.
- Keep manual-key login and the current working connection. No account writes by development tools; live writes occur only when the owner approves them in the phone UI.
- Rollback only resources created by this attempt. Report ambiguous requests/cleanup failures without blind POST retries.

## Tasks and interfaces

1. IAMSetupAPI: discovery, paginated project listing, provisioning permission preflight, strict policy creation and readback, application-bound key creation, typed minimal key verification, targeted cleanup. Tests assert fixed HTTPS origin, headers, exact scopes, no user key, empty/foreign project rejection, refusal of denied/malformed/redirected responses and bounded propagation retries.
2. AutomaticSetup: memory-only verified session, scope selection and explicit creation gate, transactional setup/cleanup and safe commit. BrowserLogin hands a verified envelope to this coordinator without changing the working experiment path. Tests cover no writes before approval, policy/key/verification/save failure, cancellation during a POST, stale selection/session, rollback failures and no old connection overwrite.
3. DashboardStore: adopt verified credentials only after successful vault save; freeze concurrent credential mutations across the commit; clear old account data on success. Tests cover replacement success, Keychain failure, in-flight disconnect and cancellation at commit.
4. BrowserSetupView and ConnectionView: native sheet from pre-login and connected Account, browser handoff, Organization/project chooser, scope summary, explicit approval, progress/cancel/cleanup results and manual fallback. Preserve debug-only diagnostics.
5. Full macOS core suite, iPhone Debug/Release builds, independent static review, physical install if connected. Manual sign-in and explicit provisioning approval are the final device gate.

## Review focus

- Ambiguous POST responses and process termination must not trigger duplicate keys or delete existing resources.
- Cancellation after a successful POST must capture the returned ID before rollback.
- Empty Instance results cannot prove scoped access: check the newly created policy scopes and selected project permissions separately.
- Keychain save is the commit point: no cancellation/cleanup may revoke the now-saved key.
- Organization/project changes while reads complete cannot authorize stale scopes.

## Execution ledger

- Existing codex/api-key-dashboard checkout has prior uncommitted app work; preserve it. No commits/push requested.
- API references refreshed through Context7 plus official IAM/Account docs and SDK. Provisioning permission identifiers confirmed in the publicly served console map (iam:application:create, iam:policy:create, iam:api_key:create; corresponding delete permissions for cleanup). API check-permissions contract requires exactly one project_id or organization_id.
- Design choice: keep automatic setup available in ordinary builds with a clear unsupported browser-flow notice, while the existing diagnostic experiment remains Debug-only. No production release or publication is part of this work.
- IAM boundary tests failed before implementation; core client then passed. Transaction and atomic replacement tests likewise failed before their interfaces existed and subsequently passed.
- Initial integrated core suite: 51 passing; cancellation, propagation, save-commit and recovery cases expanded it to 60 passing.
- Independent final static review found known-ID cleanup hidden by renamed resources and expiry during recovery retaining a session. Both reproduced as failing assertions and fixed. Known resources now read directly by ID; expiry clears the session independently of cancellation.
- Additional provider documentation established AllApps group inheritance. Added a failing regression proving setup could otherwise create a broader key, then blocked any additional direct/group/AllApps policy before key creation and again before commit. No existing policy is edited.
- Added unknown POST outcome and malformed recovery record checks; malformed record initially failed to disable setup, now fails closed with an explicit manual recovery path. No remaining deferred review findings.
- Full core suite: 65 passed, zero failures. Signed physical Debug and generic unsigned Release compilation succeeded; final reviewed build and read-only device-navigation check being prepared. No simulator started, no account writes from development tools.

- Final verification: 65 macOS core tests passed; signed physical iPhone build-for-testing and unsigned generic iPhone Release build passed. Update installed in place and launched normally, retaining the saved account.
- Focused physical UI check testAutomaticSetupCanOpenAndReturnWithoutSigningIn passed (1/1, 19.453 seconds). Pre-sign-in dark screenshot reviewed: readable wrapping/contrast and no clipping. No browser pages/screenshots or account writes automated. Results outside repository at /tmp/scaleway-automatic-setup-ui.xcresult.
- Owner asked to perform browser sign-in, choose scopes, approve creation in the app, and report the result. Live provisioning and saved replacement still pending; password/MFA/SSO not retested.
- Ruling: existing group/AllApps policy inheritance must be absent for automatic setup to guarantee requested scopes; refuse setup rather than modify existing policies. Cost if wrong: conservative fallback may require a manual key on an Organization whose inherited rules happen to be equivalent.
- No commits or pushes performed. No simulators started. No remaining deferred static review findings.

- Owner-confirmed live acceptance: “Connected and dashboard data matches.” This confirms the automatic sign-in/scope-selection/approval/provision/verify/save/dashboard flow on the physical iPhone. No live creation or authentication was driven by automation.
- Implementation and main device acceptance complete. Live cancellation/recovery and restoration of the replacement after relaunch remain untested; password/MFA/SSO not retested. No additional tests, simulator runs, screenshots or account changes performed after owner sign-in.
