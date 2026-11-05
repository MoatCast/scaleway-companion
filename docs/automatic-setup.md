# Automatic read-only connection setup

Implemented 4 November 2026. The browser/passkey handoff was previously confirmed on a physical iPhone by the owner. The owner subsequently confirmed that automatic setup completed on the physical iPhone and the connected dashboard data matches the account.

## Experience

From the connection screen choose **Continue with Scaleway**, or from connected Account choose **Set up a read-only connection**. Sign in on Scaleway’s real website. Select an unlocked Organization from the authenticated user’s connections, then select projects explicitly. No project is selected by default.

The permission summary names the selected projects and explains:

- A dedicated IAM application, one policy and an application-bound key will be created.
- InstancesReadOnly applies only to those project UUIDs.
- BillingReadOnly applies to the entire chosen Organization and includes more than consumption, such as other billing information.
- The temporary browser session can have broader account permissions. It remains only in memory and is discarded after setup, cancellation or expiry (at most ten minutes waiting in the app).
- Existing credentials and connection remain active until the verified replacement is saved. The previous API key is not revoked.

Only **Create read-only connection** authorizes the app to provision resources. The manual-key form remains available, including when the sign-in cannot provision or verify the required access. There is no app backend or password form.

## Provisioning and verification

1. Refresh the chosen Organization’s project list and check creation/deletion permissions for applications, policies and API keys using IAM check-permissions. Fail closed on missing or unrecognized decisions.
2. Create a uniquely named `Companion-<UUID>` application and a policy with exactly the two approved scope rules. No user ID, wildcard project selection, IAM privileges or other permission sets are sent.
3. Read the policy and rules back from Scaleway and verify the application, Organization, exact project set and permission names. Reject conditions, deny rules, added scopes and account-root rules.
4. Inspect paginated groups and policies for the Organization to ensure no other direct, group or AllApps policy applies to the new application. If inherited access is found or cannot be verified, stop and roll back; do not change existing policies. Repeat the policy and inheritance checks immediately before saving.
5. Create an API key specifying only the new application as bearer. Reject a response that names a different application or a user bearer.
6. With the new key, perform typed, minimal Instance reads filtered separately to each chosen project in Paris 1, plus current UTC-month consumption for the Organization. Empty results are accepted only alongside the verified policy scope; they alone do not prove permissions. Retry initial 401/403 read failures at most 13 attempts with five-second gaps (60 seconds of propagation waiting). POST creation requests are never retried automatically.
7. Save the application key to device-only Keychain. This is the commit point and cannot be cancelled midway. Until save succeeds, the old key and account data remain intact. After saving, reset old data, refresh using the new key and discard the browser session. Permission checks are a snapshot; Organization administrators can change access later.

All authenticated requests target fixed `https://api.scaleway.com` endpoints, refuse redirects, bound responses and show sanitized errors. Session and renewal tokens are never stored in preferences, Keychain, logs or screenshots. Only the restricted application key is saved to Keychain. Diagnostic browser sign-in remains separately available in Debug builds.

## Failure, cancellation and recovery

Before creation the app records a non-secret recovery receipt containing the Organization, unique resource name, known resource IDs and an uncertainty flag. It never contains session tokens or a secret key. Successful responses are decoded and journaled before honoring cancellation.

Failures trigger a separate cleanup task, even if the setup task was cancelled. Known resource IDs are read directly and validated against this attempt before deletion. Name discovery is reserved for unknown IDs, with exact Organization/name/bearer checks. A renamed or mismatched resource retains recovery for manual inspection; an empty name-filtered listing cannot conceal a known resource. Deleting the attempt’s application revokes its keys, including a key whose creation response was lost. Existing applications, keys and policies are never cleanup targets.

A lost/ambiguous POST can finish after a listing returns empty. Such uncertainty is retained, blocks duplicate setup, and requires checking the named resources in Scaleway. Cleanup failures and unreadable local records remain visible with a manual recovery path. Clearing a record requires the user to acknowledge checking Scaleway; clearing does not itself delete or revoke anything.

The committed credentials include the unique setup name. After a process interruption, recovery recognizes a saved connection with that name and clears the stale receipt without revoking the committed key. Disconnect continues to mean local credential removal; revoke the application/key in Scaleway to remove remote access.

## Evidence and remaining checks

- 65 macOS core tests pass, including exact request scopes, pre-approval no writes, foreign/malformed responses, policy widening, inherited AllApps access, cancellation during creation, propagation bounds, save failure rollback, cleanup failure, renamed resources, uncertain outcomes, malformed journals, session expiry during cleanup and saved-connection recovery.
- Independent static review found two recovery issues, both reproduced with failing tests and fixed. Additional scope and journal regressions pass. No deferred review findings.
- Final signed Debug build-for-testing and unsigned Release iPhone builds pass without a simulator. The update was installed in place and launched normally on the owner’s connected iPhone.
- One focused physical-iPhone UI test passed: open automatic setup, confirm provisioning is unavailable before sign-in, then return through the existing-key fallback. The pre-sign-in dark-mode screenshot was reviewed for wrapping, contrast and clipping. No browser login or IAM write was automated.
- **Owner-confirmed live acceptance, 4 November 2026:** browser sign-in, Organization/project selection, explicit creation approval, IAM application/policy/key setup, verification, Keychain saving and dashboard connection completed on the physical iPhone; dashboard data matches the account. This is owner-reported acceptance, not an automated live provisioning test or an independent console audit.
- Live cancellation/recovery and replacement-key restoration after relaunch remain untested on the physical device; those state paths have fixture coverage. Password/MFA and SSO were not retested. No account mutation was performed by development tools; provisioning was approved and executed by the owner through the app.

The browser handoff remains unsupported by Scaleway and may change without notice. This implementation is not a registered third-party OAuth/PKCE integration.

API references: [IAM API](https://www.scaleway.com/en/developers/api/iam/), [key bearer](https://www.scaleway.com/en/developers/api/iam/api-keys), [project discovery](https://www.scaleway.com/en/developers/api/account/project/projects), [IAM schemas including AllApps groups](https://www.scaleway.com/en/developers/api/iam/~schemas), [policy inheritance](https://www.scaleway.com/en/docs/iam/policies-permissions/policy/), [Instance API](https://www.scaleway.com/en/developers/api/instance/).
