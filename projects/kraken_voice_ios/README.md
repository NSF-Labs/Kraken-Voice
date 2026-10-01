# Kraken Voice iOS

Independent iOS conversion of the current Kraken Voice Flutter source, copied
on 2026-09-27 from the Android working tree (including its uncommitted changes).
Source lives here; the Android project is not used at runtime.
Dart package name remains `krak_en_voice` to preserve internal imports.

- App: **Kraken Voice iOS**, version **0.1.9+10**
- Bundle identifier: `org.krak-en.voice.ios`
- Deployment target: iOS/iPadOS 17.0 or later
- Xcode workspace: `ios/Runner.xcworkspace`

## First conversion milestone

Implemented: AVAudioRecorder capture into persistent Documents/recordings,
permission handling, pause/resume/stop, amplitude events, duration lookup,
audio input selection, interruption saving, recording time limits, iOS
notifications, and iPad share popover anchors. Channels register after Flutter's
implicit engine initializes, supporting the UIScene lifecycle.

Carried over for device testing: encrypted vault, recording list, folders,
playback, audio export, calendar screens and preferences.

Whisper is bundled and installed with SHA-256 verification at first launch, without
network access. `scripts/prepare_models.sh` fetches the pinned build asset.
Gemma uses a vendored copy of FWPlanner's Gemma4Swift/MLX runtime
with documented shared-KV and quantized-projection fixes with model setup, progress,
cancellation, readiness checks and token budgeting. This build requires at least
6 GB of physical-device RAM for Gemma. Simulator Gemma inference is unavailable.

Pending: incoming share extension and
long-running background AI processing.
The iOS background task API gives limited execution time; it does not reproduce
Android's indefinite foreground service. Recording uses the audio background mode.
Silence-triggered voice commands are not implemented in this milestone.

## Build and load

Google Drive attaches metadata that Apple's code signer rejects. Use a disposable
build copy outside cloud storage; always edit the source in this project.

```sh
./scripts/stage.sh
cd /private/tmp/kraken_voice_ios_build
flutter pub get
flutter build ios --debug --no-codesign  # compilation only
flutter devices
flutter run --release -d DEVICE_UDID    # sign, install and launch on hardware
```

The Xcode project selects the user's confirmed Apple Developer team
`ZVCZM72MN3`. Xcode must have that account signed in and be able to provision
`org.krak-en.voice.ios`. Connect/unlock the device, trust this Mac, and enable
Developer Mode if iOS requests it. See Flutter's official setup instructions:
https://docs.flutter.dev/platform-integration/ios/setup

To rebuild, install and launch in one command from this project:

```sh
./scripts/install_device.sh 00008130-000A48A11408001C
```

## Device acceptance checks

1. Complete preview onboarding; deny microphone once and verify Settings recovery.
2. Record speech, pause, resume, stop; confirm the saved entry plays correctly.
3. Lock the phone while recording; unlock and stop; verify complete playback.
4. Receive a call/Siri interruption; verify recording is saved, not left active.
5. Relaunch and verify recordings and folders persist.
6. Export audio through the system share sheet on both iPhone and iPad.
7. Verify the recording time limit stops and saves the file.

Native recording smoke test (permission must be granted on the device):

```sh
flutter test integration_test/ios_recording_test.dart -d DEVICE_UDID
```

No physical-device acceptance result should be inferred from compilation or Dart
unit tests. TestFlight/App Store submission is a later release step.

## Validation — 2026-09-27

- iPhone debug build without signing: passed.
- Signed iPhone release build: passed (89.4 MB).
- Recording safety, trial export and processing regression tests: 17 passed.
- Final static analysis: no errors or warnings; 25 informational lint findings.
- Added `integration_test/ios_recording_test.dart`; hardware execution pending.
- Apple Silicon simulator limitation: the inherited FFmpeg plugin does not
  provide the required arm64 simulator slice. Hardware builds work; simulator
  support needs a dependency change in the next conversion milestone.

Build staging directory is disposable. Re-run `scripts/stage.sh` after source
changes; remove stale source files there manually if a later conversion deletes
or renames files.

## Signing and deployment

Use **ZVCZM72MN3 only** for this project. The user explicitly confirmed this team
and reports accepting its updated agreement. Do not select a different team from
cached accounts or certificates.

Target: iPhone 15 Pro Max (`00008130-000A48A11408001C`). Device-specific
provisioning succeeded with the confirmed team. The release preview was installed
and launched successfully on this iPhone using `devicectl`. Recording/playback
acceptance checks still require hands-on testing.

## Whisper conversion — 0.1.1+2

The AI Models screen now downloads Whisper base (147,951,465 bytes), displays
progress and errors, allows cancellation/retry, and verifies the pinned SHA-256
before committing the model file. Gemma is explicitly marked unavailable. Returning
from Settings model management goes back to Settings. iOS transcription no longer
calls the missing Android inference bridge or attempts automatic Gemma summaries.

Validation: seven model-download/UI tests passed; static analysis has no errors
or warnings (26 informational findings). A release qualification build downloaded
and verified Whisper on the iPhone 15 Pro Max, converted a generated AAC sample,
and transcribed it correctly in 879 ms. See `docs/IOS_WHISPER_CHECK.json`.
The test downloaded Whisper into the app's model directory, so it is already
installed on this phone; the download prompt will still appear on a fresh install.
The generated sample is `assets/qa/whisper_check.m4a`; qualification entry point:
`lib/qualification/ios_whisper_check.dart`. This check does not record or use user audio.

FWPlanner's existing iOS Gemma source was located; see
`docs/FWPLANNER_IOS_REFERENCE.md` for the MLX integration details.

The normal 0.1.1+2 app was signed with ZVCZM72MN3, installed and launched on the
iPhone 15 Pro Max after qualification. The temporary test screen was replaced.

## Icon update — 0.1.2+3

The iOS icon now uses the Android adaptive icon background color `#0D0D1A`.
The development-only launcher icon generator is vendored under
`tool/flutter_launcher_icons` with a two-channel alpha-blending correction;
upstream 0.14.4 mixed background alpha into green, creating bright green fringes
when flattening the transparent logo over a dark color. The corrected generated
1024px icon was visually checked. Regenerate using `dart run flutter_launcher_icons`.

Version 0.1.2+3 was signed with ZVCZM72MN3, installed and launched on the iPhone
15 Pro Max on 2026-09-28.

## Model and simulator update — 0.1.4+5

FFmpeg is pinned to 3.6.2 for native arm64 simulator support. Simulator builds
select arm64 because the Whisper pod excludes Intel kernels. Xcode's Metal
Toolchain component is required for MLX. Swift package revisions are locked to
the FWPlanner reference versions.

Run `scripts/test_simulator.sh SIMULATOR_UUID` against a booted simulator.
`lib/qualification/ios_models_check.dart` installs models and checks generated
speech and a synthetic meeting note on hardware; restore `lib/main.dart` afterward.
Qualification does not read user recordings. The Gemma model is downloaded into
persistent app storage; Whisper is included in the app bundle. Historical results
above apply only to their specified builds; current results are recorded in
`docs/IOS_DEVICE_TESTING.md`.

Whisper's iOS-only plugin fork under `tool/whisper_ggml_plus` selects CPU inference
for Simulator while preserving Metal on hardware. Run `scripts/prepare_models.sh`
before running tests directly from a fresh checkout. The model bytes are ignored
by Git and downloaded from the pinned revision with checksum validation.

## App Store release preparation — September 30, 2026

The user reports the existing app passed hands-on testing on all three devices.
The new purchase flow requires separate sandbox acceptance before submission.

The iOS release entry point now uses verified StoreKit 2 transactions. A free
non-consumable `krak_en_voice_30_day_trial` grants 30 days from Apple's original
purchase date; `krak_en_voice_full_unlock` grants permanent access. Configure the
latter at **US$9.99** in App Store Connect; the app displays Apple's localized
price. No subscription or automatic charge is involved. Recording and AI require
an active trial or unlock; saved work remains available for viewing, playback,
export, and deletion. Existing user-selected retention policies still apply;
trial expiry does not trigger the inherited free-tier storage-cap deletion.

Privacy URL: https://krak-en.org/voice/privacy-policy (deployed and fetched
successfully). Source is `release/privacy/`; Cloudflare Worker
`kraken-voice-privacy` serves only the policy route on `krak-en.org`.

App Store Connect values are in `release/app-store-setup.json`. Both products, English localizations, prices, and the free offer are
now created in App Store Connect (app ID `6817940644`). Use team `ZVCZM72MN3` and bundle
`org.krak-en.voice.ios`. Create both non-consumables, add localization, price,
availability and purchase review screenshots, and submit them with the app's
first purchase-enabled version. Complete the Paid Apps agreement, tax and
banking setup if App Store Connect requests them. Configure the app itself free.

For freebies, create a **Free Offer** on the lifetime unlock named
**Voice Lifetime Gift**, with all three purchase-history eligibility groups so
claiming the free trial does not exclude a recipient. Select the app's intended
storefronts. Create sandbox codes first (minimum 10). For production, Apple
requires the app to be **Ready for Distribution** and the purchase **Approved**.
Generate unique one-time-use codes (minimum batch 500), choose an expiry within
six months, download the CSV privately, and give each person one code or its
Apple redemption URL. Codes are redeemed in Settings > Trial & Lifetime Unlock
> Redeem Offer Code, or through the App Store. Do not commit the codes to Git.
An expired unused code does not revoke a lifetime unlock already redeemed.
Ten sandbox codes have been generated and saved privately under
`/Users/zebulon/.appstoreconnect/offer-codes/`. No production codes have been
generated; sandbox codes are for testing only.

`ios/KrakenVoice.storekit` provides matching local Xcode test products. Select it in a local Run scheme's StoreKit Configuration
for testing; do not use local StoreKit configuration as proof of live product
setup. Test a fresh trial, exact expiry, cancelled and pending purchases, lifetime
purchase, offline relaunch, restore on another device, refund/revocation, and
sandbox code redemption. Confirm saved audio and exports remain accessible
after expiry. The user confirmed a successful Sandbox trial activation on September 30, 2026.
Lifetime purchase, restore, expiry, and offer-code redemption still need their own acceptance checks.

Review notes: Open Settings > Trial & Lifetime Unlock to start the free 30-day
trial, buy the lifetime unlock, restore, or redeem a code. No app account is
required. Trial expiry blocks new recording and AI processing; existing content
remains available. Models process audio and text locally. Gemma requires an
initial download and compatible hardware. Privacy Policy is in Settings and
the purchase dialog.

Before upload: choose the release version/build, complete App Privacy answers
against the actual binary and third-party SDKs, supply App Store screenshots,
support URL and reviewer contact information, and run the sandbox checks above.
Rate/Share App links now use the actual App Store ID `6817940644`. See the
release status section below for the current archive and submission state.

Apple references:
- Trial rules: https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
- Offer setup and code requirements: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases

Validation of this preparation: 27 targeted Dart tests passed (purchase/trial
states, recording safety, export, retention and background processing). The
unsigned device release build compiled successfully. Full analyzer output had
no errors or warnings, with informational lint findings in existing code and
vendored tools. App-owned UserDefaults and file-timestamp reasons are declared
in the bundled `PrivacyInfo.xcprivacy`; this does not replace SDK or App Store
Connect privacy review.

### NSF Labs App Store Connect API access

Key `H3426ABVMJ` (NSF Labs), issuer `277c068d-1703-4392-9c1b-16c55e1c3c6a`,
was verified against developer team `ZVCZM72MN3`. The private key is stored only
on this Mac at `/Users/zebulon/.appstoreconnect/private_keys/AuthKey_H3426ABVMJ.p8`
with permissions `0600`. Other authorized agents running as this user can use
it; never print its contents, tokens, or copy it into a repository. The original
download remains in Downloads.

From this project's root, read the app record with:

```sh
ASC_PRIVATE_KEY_PATH=/Users/zebulon/.appstoreconnect/private_keys/AuthKey_H3426ABVMJ.p8 \
  node scripts/app_store/api.mjs GET '/v1/apps?filter[bundleId]=org.krak-en.voice.ios'
```

The explicit bundle ID is registered as Apple resource `G789H66D9S`, with
In-App Purchase capability. The Voice app record now exists as `6817940644`, SKU `kraken-voice-ios`.
Apple currently displays its user-entered name as `Kracken Voice IOS`.
Live configuration evidence is in `release/app-store-verified.json`.
The download is free, trial is free, and lifetime unlock is US$9.99, with
Apple-managed equivalent regional prices and availability in 175 territories.
The `Voice Lifetime Gift` free offer includes all purchase-history groups.
Sandbox batch `a6ccf8a4-b6dd-4d43-bd85-ea5abb270f56` contains ten test codes
and expires March 1, 2027; its CSV is stored privately outside this repository.
Production codes remain unavailable pending Apple approval and distribution readiness.

Store-side verification after setup: both purchases are **READY_TO_SUBMIT**.
Apple processed both review screenshots successfully (`COMPLETE`). The actual
app loaded the live StoreKit product details in the iPhone 17 Pro simulator and
rendered the free trial and $9.99 purchase buttons; the screenshot integration
test passed. This verifies product loading and UI only, not a completed purchase,
restoration, or offer redemption. `release/screenshots/purchase-review.png` is
an unedited simulator capture used for purchase review, not public marketing.
The app remains in preparation; no build or purchase was submitted for review.

## iPhone microphone graph correction — 0.1.8+9

The native iOS recorder emits average power in negative dBFS, while the dashboard
previously interpreted all incoming values as positive Android 16-bit peaks.
That discarded iPhone speech as silence. The audio bridge now emits consistent
dBFS on both platforms; the iOS display uses a -60 dBFS floor so quiet speech
remains visible. Sensitivity and smoothing still control the display only.

Four regression tests passed for iOS speech, platform normalization, sensitivity
and invalid values. Targeted analysis reported no errors or warnings. The user confirmed that the microphone visualizer works on the physical iPhone.
Signed build 0.1.8+9 compiled, installed, and launched successfully on the
connected iPhone 15 Pro Max (`00008130-000A48A11408001C`). The user subsequently confirmed live voice/graph acceptance.

## Public user guide and remaining submission work — September 30, 2026

- User guide and support: https://krak-en.org/voice/user-guide
- Privacy policy: https://krak-en.org/voice/privacy-policy
- Both public HTTPS pages returned 200 and their expected content.
- Guide source, Worker, configuration, and deployment evidence: `release/guide/`.
- The guide covers setup, recording, models, transcription, summaries, chat,
  imports, exports, calendar, retention, backups, access, and troubleshooting.
- Guide route is separate from the privacy route and the main website.
- Seven user-selected iPhone screenshots and one 13-inch iPad screenshot
  are uploaded and COMPLETE. Use actual app
  screens without debug banners or personal data. Recommended scenes: Home,
  an example transcript/summary, organized Files, and export options.
- Apple accepts 1–10 screenshots per set. Suggested portrait sizes: iPhone
  6.9-inch 1320×2868 and iPad 13-inch 2064×2752. Verify specifications at
  https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- The listing description was empty and no builds were uploaded when checked.
  Complete listing metadata, App Privacy, age rating, review details, and build
  upload before submission. Confirm required business agreements in Connect.
- The document-import release issue found during the guide audit is resolved
  in 0.1.9+10, as described below. The published guide now includes import steps.

## PDF and Word import — 0.1.9+10

PDF text extraction now runs through PDFKit on a serial background queue.
Word .docx extraction reads the body XML in a Dart isolate, preserving tables,
Unicode, paragraph breaks, and accepted text while omitting deleted revisions.
Neither path sends document content over the network. Limits: 50 MB source,
200 PDF pages, 8 MB Word body XML, and 500,000 extracted characters. Scanned
PDFs need OCR first. Partial PDF extraction and Word omissions are shown in the
document detail view. Existing PDF/Word export code is unchanged.

The seven user-selected iPhone screenshots are IMG_0022.PNG–IMG_0028.PNG
(1290×2796), copied without image edits into `release/screenshots/iphone/`.
Their original modification times did not reflect the order added to Downloads.
The upload manifest records the corresponding draft App Store assets.

Validation: eight Dart tests passed for Word parsing and document persistence;
targeted Dart analysis reported no issues. The iOS simulator integration test
passed for real PDFKit extraction, Word body/table/Unicode extraction, deleted
revision exclusion, blank/corrupt inputs, and mixed text/blank PDF page warnings.
Seven screenshot asset delivery states were verified COMPLETE in App Store
Connect. Screenshot uploads do not submit or publish the app.
Signed release 0.1.9+10 built successfully, installed, and launched on the
connected iPhone 15 Pro Max. Manual import through Files/iCloud with the user's
own PDF and Word documents remains the final device acceptance check.

The 13-inch iPad Pro was updated to 0.1.9+10. The user supplied
`IMG_0055.PNG` (2064×2752) showing the active recording visualizer. The original
was copied unchanged to `release/screenshots/ipad/` and Apple verified the
iPad screenshot asset as COMPLETE. Both required device screenshot sets now exist.


## Distribution build 1.0.0 (12) — September 30, 2026

The production archive and App Store-signed IPA built successfully outside
Google Drive. The initial archive passed Apple's `altool --validate-app` with
no errors. Final packaging includes the existing kraken art on the native
launch screen, the `Krak-EN Voice` display name, and real App Store URLs in
Settings. No PDF/Word export behavior was changed.

- Package identity and SHA-256: `release/release-build.json`.
- Listing copy and reviewer instructions: `release/store-metadata.json`.
- Applied App Store metadata: `release/store-metadata-applied.json`.
- Prepared submission and purchase items: `release/review-submission.json`.
- Privacy/export-compliance evidence: `release/compliance-review.json`.
- Upload log: `/private/tmp/voice-release-build12-upload.log`.

The listing is named **Krak-EN Voice**, category Productivity, with a 13+
developer age override matching the published policy's intended audience.
Review contact, support URL, policy URL, and both screenshot sets are saved.
The trial and lifetime IAP versions have been added to the same prepared
review submission. Submission is not complete until the build is processed,
attached, export compliance is resolved, App Privacy answers are published,
and Apple accepts the final submit request.

Build 11 uploaded successfully and processed as valid, with a missing location
purpose-string warning from the transitive DKCamera photo-picker dependency.
Build 12 includes the accurate optional-photo-tagging description Apple
requires for this bundled code. The SDK's GPS tagging remains disabled by
default; no new location request or collection was enabled. Build 12 uploaded
successfully (delivery `f56cdfc4-4387-4ec7-8842-530c50f486f4`).

App availability is set to 174 territories, with France excluded because no
French encryption declaration is available. The non-France configuration uses
Apple's documentation-exempt build answer for standard encryption; it does
not assert that the app contains no encryption. See
`release/export-compliance.json` and `release/compliance-review.json`.
Apple preflight confirms the owner has published App Privacy answers.


### Submitted to Apple

On September 30, 2026 at 10:48 PM America/New_York (October 1 at 02:48 UTC),
Apple accepted review submission `74904eac-7d70-4393-b45a-84e3dbb1d3c9`.
**Krak-EN Voice 1.0.0, build 12, is WAITING_FOR_REVIEW.** Both initial
In-App Purchase versions are included in that same submission. The release
setting remains `AFTER_APPROVAL`. See `release/submission-result.json` and
`release/submission-verified.json` for the server responses.

Production one-time offer codes remain a post-approval task: Apple requires
the app to be Ready for Distribution and the purchase Approved. The lifetime
free offer and sandbox codes already exist.

### Cross-platform public documentation (September 30, 2026)

Published the Android/iPhone/iPad privacy policy and full user guide at:
- https://nsflabs.org/voice/privacy-policy.html
- https://nsflabs.org/voice/user-guide.html

Canonical source remains `release/privacy/privacy-policy.html` and
`release/guide/user-guide.html`. All three generated `worker.mjs` files embed
these documents; regenerate their embedded strings when changing the HTML.
The existing krak-en.org App Store links also serve the updated documents.
Android free limits, Google Play purchases, selected hardware support, and
Android 15 PDF extraction are distinguished from Apple's 30-day trial.

The NSF Labs Pages source was not redeployed. Worker `kraken-voice-docs`
serves `/voice/*`; exact homepage `/` and `/index.html*` routes use HTMLRewriter
to update only `article#voice` document links and its note in the current
Pages response. Unmatched requests pass through to origin. This preserves
other apps and their assets. When incorporating these links into the Pages
source later, update its Voice card before removing the homepage routes.
Route/deployment IDs and live checks are in `release/nsflabs/`.

### Direct Pages publication supersedes the Worker integration

The documents and homepage links are now physical assets in the `nsflabs`
Cloudflare Pages production deployment `890c8ae3` (branch `main`). The full
preserved deployment is `release/nsflabs/pages-site/`; existing unrelated
assets were retained from the previous live production site. The Voice
files, homepage card, and app-library metadata were also saved in the existing
NSF Labs site source at `/Users/zebulon/Projects/Kraken Hub/KrakEN Quote/krak_en_quotes`.
The three NSF Labs Worker routes described above have been removed after
verifying direct Pages delivery. The krak-en.org App Store Workers remain.
A targeted cache purge was completed. `pages-verification.json` records
successful public checks, including homepage query-string access.
