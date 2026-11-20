---
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy — Companion for Scaleway

Effective 20 November 2026

Companion for Scaleway is a free, open-source iPhone app for viewing your Scaleway spending and Instances. It is an independent project and is not affiliated with or endorsed by Scaleway.

## The short version

**The app collects no data.** It has no analytics, no tracking, no advertising, no accounts of its own and no server. Everything it shows comes directly from Scaleway to your iPhone.

## What stays on your iPhone

- **Your API key and Organization ID.** Saved in the iOS Keychain, available only when your iPhone is unlocked, never synced to iCloud or included in backups to other devices, and sent only to Scaleway's API over HTTPS.
- **Account labels.** The Organization and project names chosen during setup, saved with the key so the Account screen can show them.
- **Widget snapshot.** This month's totals, the forecast and Instance counts, stored in the app's private App Group so your widgets can display them. It contains no key, project IDs or resource names.
- **Budget alert settings.** Your budget amount and which alerts were already sent this month.
- **Appearance preferences.** Your chosen theme and light/dark mode.

During browser sign-in, the temporary Scaleway session is kept in memory only and discarded after setup. Your password, passkey and two-factor codes are entered on Scaleway's own website and never reach the app.

## Who the app talks to

The app connects only to Scaleway (`api.scaleway.com`, and `account.scaleway.com` during sign-in). Requests use your key to read billing and Instance data. The only changes the app ever makes are during optional automatic setup: after you approve it, it creates one dedicated read-only IAM application, policy and API key. It never starts, stops, modifies or deletes your cloud resources. Scaleway's own [privacy policy](https://www.scaleway.com/en/privacy-policy/) applies to data Scaleway processes.

Budget alerts are local notifications created on your iPhone. No notification service or server is involved.

## Deleting your data

- **Disconnect** in the app's Account screen removes the key, loaded data, widget snapshot and budget settings from your iPhone.
- **Deleting the app** removes everything it stored.
- To revoke access everywhere, delete the API key or IAM application in Scaleway's console.

## Children

The app is a tool for Scaleway account holders and is not directed at children.

## Changes

Changes to this policy are published on this page and in the app's public source code repository.

## Contact

Questions or concerns: open an issue at [github.com/MoatCast/scaleway-companion/issues](https://github.com/MoatCast/scaleway-companion/issues).
