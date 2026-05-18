# ECS Wizard

A macOS utility for managing AWS ECS services, RDS, and CloudWatch Logs.

**Requirements:** macOS 13 or later · AWS CLI · Session Manager Plugin

---

## Installation

### 1. Download

Go to the [Releases](../../releases) page and download the latest `ECSWizard.app.zip`.

### 2. Move to Applications

Unzip the downloaded file and drag **ECSWizard.app** into your `/Applications` folder.

### 3. Remove quarantine

Because the app is distributed outside the Mac App Store, macOS will quarantine it and block it from opening. Run this command in Terminal to remove the quarantine flag:

```bash
xattr -cr /Applications/ECSWizard.app
```

### 4. Launch

Open **ECSWizard** from your Applications folder or Spotlight (`⌘ Space`).

---

## Prerequisites

### AWS CLI

Install the AWS CLI by following the [official installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

### Session Manager Plugin

Required for connecting to ECS containers. Install it by following the [official installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
