# Dashboard refinement implementation

Approved direction: taste-skill Framed sheet and the Paper handoff. Implement locally on the existing API-dashboard branch; preserve prior work. No cloud writes, hosted monitoring deployment, installation, or push in this pass.

- [x] Add failing regressions for 12-zone coverage, partial/stale data, filtering, history gaps, account replacement and monetary reconciliation.
- [x] Extend read models: each Instance carries its zone, all-zone reads use batches of three, keep per-zone last-success snapshots. Fetch six months of history on demand; reject old-account results and represent unavailable periods as missing.
- [x] Apply opaque neutral/teal design with shared SwiftUI surfaces and bottom navigation. Compact Overview; group lists; add real monthly Charts, project/zone/status/search filters, section freshness and retry states. Adapt demo, connection and account screens to the same appearance.
- [x] Verify focused tests, generic-device compilation and privacy scan without simulators. Review changes and document limitations.

Typography: Apple system font for the native app with Dynamic Type; Paper uses IBM Plex Sans. Exact Paper colour and sizing values were read through the connection. No new dependencies.

Verification: 29 simulator-free unit tests pass. Generic iOS build-for-testing compiles app and test bundles. No simulator, installation, commit or push performed. Native UI and live credentials remain unverified on a physical iPhone.

Review fixed: current-month history retry excluded cached failed months; canceled view tasks created false network errors; Overview inherited hidden Instance filters. Added regressions and independently reviewed the fixes.
