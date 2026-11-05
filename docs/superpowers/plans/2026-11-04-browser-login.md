# Browser sign-in experiment implementation ledger

Spec: owner-approved Browser-based Scaleway sign-in experiment in this chat; behavior and manual procedure in ../../browser-sign-in-experiment.md.

Scope: LoginProtocol, LoopbackCallback, BrowserLogin, SessionProbe, LoginExperimentView, debug-only connected Account entry, Package.swift, focused tests and documentation. Current dashboard authentication and saved credentials remain untouched. Existing uncommitted app work is preserved on codex/api-key-dashboard; no public push or commit requested.

Shared interfaces: callback receiver supplies the current LoginAttempt and one SessionEnvelope; BrowserLogin verifies that envelope, probes two capabilities and exposes sanitized results to the view. DEBUG guards cover the entry, view and coordinator. SessionVerifier and CloudAPI continue sharing redirect rejection.

- Callback/lifecycle tests written before implementation; observed missing-type/interface failures. Probe tests likewise failed before implementation.
- Implemented loopback-only random-port receiver, exact nonce callback validation, bounded HTTP requests, one-shot delivery, timeouts and cancellation cleanup.
- Implemented session verification and typed minimal GET capability probes; coordinator holds tokens only for the active task.
- Implemented development-only connected Account entry and status screen; no saved-key writes and no IAM/resource writes.
- Initial full core suite: 39 passing; real socket delivery and task cancellation checks expanded it to 41 passing.
- Independent read-only review identified callback acceptance vs. resumed-consumer/browser-dismissal timing. Added a regression at the receipt boundary, observed missing-interface failure, implemented synchronous receipt flag and consulted it in browser dismissal. Full core suite: 41 passed, 0 failures.
- Signed physical iPhone Debug build passed, corrected build installed in place. Automatic launch was denied because the device was locked; owner asked to unlock and manually perform the passkey flow.
- Generic iPhone Release build passed with signing disabled. Experiment UI/coordinator excluded by DEBUG guards. No simulator launched.
- Working API-key connection and data agreement were previously confirmed by the owner. The owner subsequently confirmed callback, verified session and both API reads on the physical iPhone using the existing passkey: main experiment gate passed. Continued saved-key usability after successful/failed/cancelled attempts and password/MFA/SSO remain pending manual checks.
- Added the proposed dedicated-application onboarding design after the success gate. No IAM provisioning implementation or cloud writes performed.

No deferred minor review findings or unresolved static review findings. No keys or policies created. No changes committed or pushed.
