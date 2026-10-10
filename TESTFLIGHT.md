# Pacer: private TestFlight setup

For the paid Apple Developer account owner. You can distribute Pacer by email invitation without releasing it on the App Store.

**Repository:** https://github.com/batemapf/pacer

The source code is public; TestFlight access can remain invitation-only. Your friend does not need your Apple password or an App Store Connect role.

## Before you start

- A Mac with Xcode 16 or later and an active paid Apple Developer membership.
- Access to [Apple Developer](https://developer.apple.com/account/) and [App Store Connect](https://appstoreconnect.apple.com/). Accept any outstanding agreements.
- Your friend's email address and an iPhone running iOS 17 or later.
- A 1024 × 1024 square app icon without transparency. The repository currently has no icon.

## 1. Open the project

Download or clone the latest `main` branch from the repository. Open **`Pacer.xcodeproj`** in Xcode, rather than the folder or `Package.swift`. The Swift package runs the pace-engine tests; the Xcode project builds the app.

## 2. Set up signing

In **Xcode → Settings → Accounts**, add your Apple Account.

Select the blue Pacer project, then **Pacer target → Signing & Capabilities**:

- Enable **Automatically manage signing**.
- Select your **paid developer team**.
- Use a unique bundle identifier, such as `com.yourteam.pacer`. The current identifier is `com.batemapf.pacer`; change it if unavailable to your team.

Xcode can register the app ID automatically. If registration is blocked, register the same explicit bundle ID under [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), then retry. Keep the project's background location and audio modes.

## 3. Add the app icon

Create an **Asset Catalog** inside the Pacer folder, with membership in the Pacer target. Add an **App Icon** set named `AppIcon` and drag in the 1024 × 1024 icon. Fill any additional slots Xcode requires.

In the target's **General → App Icons and Launch Screen**, select `AppIcon` as the icon source. Simply adding a PNG to the project is insufficient.

## 4. Create the App Store Connect record

In [App Store Connect](https://appstoreconnect.apple.com/), choose **My Apps → + → New App**:

- Platform: **iOS**.
- Name: an available name for Pacer.
- Primary language: your choice.
- Bundle ID: **exactly the identifier selected in Xcode**.
- SKU: any unique internal identifier, such as `pacer-private-001`.

Create the record. This does not publish the app on the App Store.

## 5. Archive and upload

Select the **Pacer** scheme and **Any iOS Device**, the generic device destination, not a simulator.

Choose **Product → Archive**. In Organizer, select the archive and choose **Distribute App → App Store Connect → Upload**. Follow the signing and validation prompts, fix any errors, and upload.

The GitHub simulator build verifies compilation, but does not validate distribution signing or App Store Connect upload readiness.

## 6. Complete TestFlight information

After processing, open the app's **TestFlight** tab. Complete missing export-compliance information according to the actual build; Pacer does not implement its own encryption.

Add a beta description, feedback email, and beta review contact details. There is no app login or demo account. Suggested review notes:

> Pacer is an outdoor jogging pace coach. Tap Start run and allow Precise Location. Coaching needs reliable outdoor GPS readings for at least 10 seconds. Set a target pace and enable Spoken coaching to hear speed-up or slow-down prompts. Target pace and miles/km can be changed during a run. There is no account or sign-in.

## 7. Invite your friend privately

Under **TestFlight → External Testing**:

- Create a group, such as **Private Pacer**.
- Add the uploaded build and submit it for **TestFlight Beta App Review**. The first external build normally requires review.
- Add your friend's email address.
- Once approved, enable testing and send the invitation if not already sent.
- Keep **Public Link disabled**.

Your friend does not need access to your developer account. Do not submit an App Store version for public release.

## 8. Install and test

Your friend installs Apple's [TestFlight app](https://apps.apple.com/app/testflight/id899247664), opens the email invitation on their iPhone, accepts it, and installs Pacer.

Allow Precise Location, play music, and start an outdoor run. Check both coaching directions, target changes, miles/km switching, and several minutes with the screen locked. Confirm music lowers during speech and returns afterward.

## Renew before 90 days

Each build expires **90 days after upload**. Upload a replacement before expiry and add it to the same external tester group. Apple may request another beta review.

In this project, increment **Bundle version** (`CFBundleVersion`) directly in **`Pacer/Info.plist`**, currently `1`, for every upload. Changing only the target's Build setting will not update the literal plist value.

Keep the paid developer membership active. See Apple's [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) for current requirements.
