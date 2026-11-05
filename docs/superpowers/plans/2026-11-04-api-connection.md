# API Connection Implementation Plan

> Execution: implement inline with executing-plans and test-driven-development. The owner explicitly requested implementation of the existing design.

**Goal:** Connect the iPhone dashboard to real spending and Instances with a restricted API key.
**Architecture:** Fixed-origin API client, device-only Keychain credentials, main-actor dashboard state, explicit demo mode.
**Tech Stack:** SwiftUI, Foundation URLSession, Security Keychain; no dependencies.
**Spec:** docs/api-connection-design.md

## Constraints and review focus

- No secrets in logs or errors; no redirected authenticated requests.
- No sample fallback after failed live requests; preserve independent section results.
- Decimal monetary parsing, separate currencies, pagination and exact organization filtering.
- Cancelled/replaced connections must never publish old account data.
- Disconnect must remove the Keychain item; report deletion failures.

## Tasks

- [x] Add API and state regression tests first. Verify failure with simulator-free Swift Package tests.
- [x] Implement CloudAPI.swift: validated credentials, paginated Instance and billing reads, exact Money decoding and sanitized errors. Test 401/403, redirects, malformed money, string/numeric units, and multiple pages.
- [x] Implement CredentialStore.swift and DashboardStore.swift: Keychain persistence, restoration, partial success, disconnect and stale-result rejection. Test using in-memory credential storage and controlled API responses.
- [x] Replace account experiment entry point with API connection form. Preserve previous dashboard as explicit demo. Add live tabs, zone/project filters, refresh and read-only details.
- [x] Update UI tests and README. Run unit regressions and generic iOS build without starting simulators. Review all changes for secrets and correctness.

## Execution ledger

- Owner approved implementation on 4 November 2026; no further design confirmation needed.
- Work in the current clean checkout; no unrelated edits exist. No public push is part of this implementation.
- Simulator-free unit tests run through SwiftPM; iOS compilation uses a generic device destination. Real account verification requires the owner to enter a key on the phone, never in chat.

- API and state tests failed before their types were implemented; 18 tests subsequently passed. Added an Instance body-count regression, observed failure (one row instead of two), fixed pagination, and reran all 19 tests successfully.
- Generic iOS app build and build-for-testing passed. No simulators or real account requests used.
- Implementation moved to local branch codex/api-key-dashboard. No commits or remote push performed.
- Independent reviewer confirmed pagination issue (fixed) and identified physical-device Keychain/live-account verification as pending.
