---
title: Support
permalink: /support/
---

# Support — Companion for Scaleway

Companion for Scaleway is a free, open-source iPhone app that shows your Scaleway spending, invoices and Instances at a glance. It is an independent project, not affiliated with or endorsed by Scaleway.

## Get help or report a problem

Open an issue on GitHub: [github.com/MoatCast/scaleway-companion/issues](https://github.com/MoatCast/scaleway-companion/issues). Include your iOS version and the steps to reproduce. Never post API keys, Organization IDs, invoices or screenshots containing account data.

Security problems: please report them privately through the repository's [security policy](https://github.com/MoatCast/scaleway-companion/security/policy).

## Common questions

**Which permissions does the app need?**
Read-only access: `InstancesReadOnly` on the projects you want to see and `BillingReadOnly` on your Organization. The app cannot start, stop, create or delete resources.

**How do I connect?**
Use *Continue with Scaleway* to create a dedicated read-only key, or paste an existing restricted API key and your Organization ID. You can also explore the app with sample data in demo mode.

**Why are amounts "estimated"?**
Spending comes from Scaleway's consumption data, which excludes tax, can lag behind usage and does not deduct discounts. Invoices show the final amounts.

**Are budget alerts guaranteed?**
No. iOS decides when the app may check in the background, and billing data can lag, so alerts are best effort.

**How do I remove my data?**
Tap *Disconnect* in Account, or delete the app. To revoke access everywhere, delete the key in Scaleway's IAM console.

## Privacy

The app collects no data. Read the [privacy policy](../privacy/).
