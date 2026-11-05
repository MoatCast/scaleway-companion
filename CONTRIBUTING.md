# Contributing

Bug reports, focused improvements and documentation fixes are welcome. This is a free, unofficial iPhone app maintained as a prototype; response times are not guaranteed.

## Report an issue

Search existing issues first, then use the bug or feature template. Include the app commit/version, iOS version and steps to reproduce. Use demo mode when possible. Never post API keys, session tokens, callback URLs, billing details, account identifiers or unredacted logs/screenshots. Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Propose a change

Open a small pull request against `main`. Describe the problem, resulting behavior, relevant checks and remaining limitations. Discuss large features in an issue before implementing them. Keep discussion constructive and respectful.

Use the native SwiftUI design and existing themes. Avoid new dependencies unless needed. Keep demo and live account data separate, preserve decimal billing arithmetic, and never weaken credential validation or restricted IAM scopes.

Run the macOS core checks in [README.md](README.md). Add focused tests for behavior changes, especially authentication, permissions, money and cancellation. UI changes need physical-iPhone verification; identify anything untested. Automated checks do not require a simulator, a Scaleway account or secrets.

Set your own signing team locally; do not commit signing identities, credentials, provisioning profiles, build output or private account data. Never perform live provisioning or resource actions without the account owner's explicit approval.

## Licence

Contributions to covered source files are provided under MPL 2.0. New source files should include `SPDX-License-Identifier: MPL-2.0`. You retain copyright in your contributions; no contributor agreement is required.
