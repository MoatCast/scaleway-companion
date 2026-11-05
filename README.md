# Scaleway Companion

[![Core checks](https://github.com/MoatCast/scaleway-companion/actions/workflows/core-tests.yml/badge.svg)](https://github.com/MoatCast/scaleway-companion/actions/workflows/core-tests.yml)

A free, open-source, unofficial native iPhone app for checking Scaleway spending and running Instances. Built with SwiftUI for iOS 26+, with no third-party dependencies or app backend. Licensed under [MPL 2.0](LICENSE), with no paid tiers, subscriptions or in-app purchases.

## Features

- **Overview:** current-month spending, running Instances and project filtering.
- **Instances:** all 12 configured zones, search, project/zone/status filters and read-only details.
- **Spending:** six calendar months, monthly selection, category breakdown and separate currencies.
- **Appearance:** Ocean, Forest, Amber and Graphite themes, plus System, Light and Dark modes. Native navigation and toolbars use Apple's Liquid Glass materials; financial data stays opaque.
- **Connection options:** browser-assisted setup of a dedicated restricted IAM application key, or manual entry of an existing key.
- **Demo mode:** fictional account data and clearly labelled simulated controls, separate from live data.

The app is an independent prototype, not affiliated with or endorsed by Scaleway. Instance power controls and hosted push notifications are not implemented.

## Connect your account

### Automatic setup

1. Choose **Continue with Scaleway**. If already connected, open **Account → Set up a read-only connection**.
2. Sign in on Scaleway's website using your configured authentication method.
3. Choose an Organization and select the projects whose Instances you want to view.
4. Review the permissions, then choose **Create read-only connection**.

The app creates a dedicated IAM application, one policy and an application-bound API key. It grants `InstancesReadOnly` only on selected projects and `BillingReadOnly` on the chosen Organization. Billing access is broader than consumption: it also covers other billing information, including invoices and payment-method information.

Setup verifies the policy scopes, checks for additional inherited policies, and tests the new key before saving it. Existing credentials remain active until the replacement is saved successfully; the previous key is not revoked. Accounts that cannot provision or verify the required access can use manual setup. See [automatic setup and recovery](docs/automatic-setup.md).

**Browser sign-in is unsupported by Scaleway for third-party clients and can change or stop working without notice.** This is a CLI-style browser handoff, not a registered OAuth/PKCE integration. Passwords, passkeys and MFA remain on Scaleway's actual website. The dashboard uses the restricted application key after setup, not the temporary browser session.

### Manual setup

1. [Create a dedicated IAM application and API key](https://www.scaleway.com/en/docs/iam/credentials/create-api-keys/).
2. Grant `InstancesReadOnly` on the projects you want to view and `BillingReadOnly` at Organization scope. Allow about a minute for policy changes to propagate.
3. Enter the secret key and Organization UUID in the connection form.

Choose **Explore demo** to try the app without credentials.

## Credentials and access

The saved API key is sent directly to Scaleway over HTTPS. It is stored in device-only Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; it is not synced or sent to an app backend. Authenticated requests refuse redirects.

Temporary browser sessions remain in memory and are discarded after setup, cancellation or expiry. Session and renewal tokens are never saved to Keychain, preferences or logs. An interrupted setup can leave a non-secret recovery record containing resource identifiers, allowing targeted cleanup without storing credentials. Uncertain creation outcomes block duplicate setup until resolved.

Disconnect removes the local key and loaded account data. To revoke access everywhere, delete the key or application in Scaleway's IAM console. The dashboard is read only; automatic setup performs the IAM creation and cleanup explicitly approved through the setup screen.

## Understanding the data

Spending is estimated consumption, excludes tax and can lag behind usage. Discounts and credits are not deducted; it is not a final invoice. Billing months use UTC. Amounts use decimal arithmetic, remain separated by currency, and totals sum the displayed rounded categories.

The dashboard checks all configured Instance zones in batches of three. Project UUIDs identify resources without requiring project-directory access on the saved key. Pull to refresh, or use the refresh control. Failed sections retain their last successful values with stale labels; failed zones and missing months are shown explicitly rather than treated as confirmed zero. Spending and Instance errors are reported separately.

## Build

Requirements: macOS, Xcode with the iOS 26+ SDK, and an iPhone running iOS 26+ for device testing. Open `ScalewayCompanion.xcodeproj` and select the **ScalewayCompanion** scheme. Set your own signing team and unique bundle identifier for a physical device; personal signing configuration is not included.

Compile for iPhone without starting a simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ScalewayCompanion.xcodeproj -scheme ScalewayCompanion \
  -destination 'generic/platform=iOS' -derivedDataPath .build/device \
  -jobs 2 build CODE_SIGNING_ALLOWED=NO
```

Run the core tests on macOS without a simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --scratch-path .build/unit -j 2
```

The Swift package covers networking, callback validation, IAM setup/recovery, credentials, dashboard state, billing and appearance preferences. The application remains a native SwiftUI Xcode project. Debug builds also expose a separate browser sign-in diagnostic in connected Account.

## Verification status

Evidence recorded on **4 November 2026**:

- **65 core tests passed**, covering authentication boundaries, scoped IAM requests, cancellation and recovery, atomic credential replacement, pagination, billing arithmetic, stale/partial data and appearance preferences.
- **Debug and Release iPhone builds passed.** Four earlier physical-device UI scenarios passed, plus a separate automatic-setup open/return check. Selected native screens were visually reviewed on iPhone.
- **Manual real-account acceptance:** API-key data matched the console and restored after relaunch. The passkey browser experiment verified its callback, session and both API reads. Full automatic IAM setup subsequently completed on a physical iPhone, and the resulting dashboard data matched the account.

The 65 core tests were rerun successfully on **5 November 2026** before publishing this update. No simulator or device test was run for that publication check.

Live cancellation/recovery, restoration of the automatically provisioned replacement key after relaunch, Keychain deletion, larger text and accessibility overrides remain unverified on device. Password/MFA and SSO were not retested. Core credential-state tests use an in-memory vault. Manual acceptance is not a provider-support guarantee or an independent console audit.

## Implementation notes

- [API connection design](docs/api-connection-design.md)
- [Automatic setup, permissions and recovery](docs/automatic-setup.md)
- [Browser sign-in experiment and evidence](docs/browser-sign-in-experiment.md)
- [Historical rejected custom-scheme experiment](docs/parked-browser-experiment.md)

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports, pull requests and local checks. Report vulnerabilities privately through [the security policy](SECURITY.md), and never include credentials or account data in public issues. GitHub Actions runs macOS core checks without cloud credentials or a simulator. CodeQL scans the core Swift library on changes and weekly; it does not build or analyze the SwiftUI/UIKit application targets. Dependabot proposes updates to pinned workflow actions.

## Licence

Original source code is licensed under the [Mozilla Public License 2.0](LICENSE), SPDX `MPL-2.0`. Contributions to covered files use the same licence. Third-party names and trademarks remain the property of their respective owners.
