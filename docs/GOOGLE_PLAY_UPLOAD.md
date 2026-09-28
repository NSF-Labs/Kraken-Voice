# Google Play Internal testing uploads

The app already exists in Internal testing. The local workflow targets only
`org.krak_en.voice` on the `internal` track. It does not manage production,
store listings, billing products, device exclusions, or tester lists.

## Current setup status

- Successfully uploaded and committed **1.0.19 / version code 19** to Internal
  testing for `org.krak_en.voice`. A separate API read confirmed track `internal`,
  release `1.0.19`, version `19`, status `completed`.
- AAB SHA-256: `4ba6d6b2b300a70c1ef6c02967393457d5c789d75fa92384a8c4b3303828fd62`.
- Signing uses the supplied existing upload keystore; Play accepted the bundle.
- The service-account file is configured by path in ignored `.secrets/play-upload.json`;
  private key material is not copied into the repository. `--credentials` can override it.
- Google Play rejected build 18's Billing Library 7.1.1. Build 19 uses
  `in_app_purchase` 3.3.1 / Android plugin 0.5.3 and Billing Library 8.0.0.
- 38 regression tests passed. Static analysis found no errors/warnings (24 info
  findings). Signed AAB identity/runtime checks passed after a clean rebuild.
- Successful API commit does not independently verify tester download availability
  or an actual paid purchase. Production rollout was not changed.

## One-time access and signing setup

1. In Google Cloud, select a project and enable **Google Play Android Developer API**.
2. Under **IAM & Admin → Service Accounts**, create `kraken-play-publisher`.
   Record its service-account email. A Cloud project Owner role is not required
   merely to call the Play publishing API.
3. In **Play Console → Users and permissions**, invite that email, grant access
   to Krak-EN Voice, and enable **View app information (read-only)** and
   **Release apps to testing tracks** for the app.
4. For local automation, create a JSON key on the service account's **Keys** tab.
   Store it outside the repository, for example
   `~/.config/kraken/play-publisher.json`, readable only by your user. Set
   `GOOGLE_APPLICATION_CREDENTIALS` to that path. Do not paste the key into chat.
   A future CI workflow can use workload identity instead of a stored JSON key.
5. Bring the existing Play upload keystore onto this Mac. Update only `storeFile`
   in the ignored `android/key.properties` to its real absolute path. Preserve
   the existing alias/passwords. Compare its certificate SHA-256 with Play
   Console's **App integrity → Upload key certificate** before the first upload.
   If the key is lost, use Play's upload-key reset process rather than inventing
   a replacement key and assuming it will be accepted.
6. Confirm the Play app package is `org.krak_en.voice`; the S24 sideloaded build
   uses `org.krak_en.voice.dev`, which is a separate installation.

Official references:
[API access](https://developers.google.com/android-publisher/getting_started),
[Play permissions](https://support.google.com/googleplay/android-developer/answer/9844686),
[app signing](https://support.google.com/googleplay/android-developer/answer/9842756).

## Build, inspect, and upload

From the repository root:

```sh
python3 -m venv .venv-play
.venv-play/bin/pip install -r scripts/play-requirements.txt
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/kraken/play-publisher.json"
sh scripts/build_play_bundle.sh
.venv-play/bin/python scripts/play_internal.py --notes-file docs/PLAY_RELEASE_NOTES.txt
.venv-play/bin/python scripts/play_internal.py --notes-file docs/PLAY_RELEASE_NOTES.txt --upload
```

The first Python invocation verifies locally without connecting to Play. The
second creates an edit, checks known APK/bundle version codes, uploads the AAB,
compares Google's checksum, assigns it to Internal testing, validates, and
commits. The command rolls out the release to Internal testing subject to Play
processing/review. It writes `build/play-internal-receipt.json` after a confirmed
commit. It does not claim immediate tester availability.

If validation/upload fails, the pending edit is discarded when possible. If
commit has an uncertain network outcome, the script stops and reports the edit
ID for inspection instead of automatically retrying. Avoid editing this app in
Play Console while the upload is running.

Before another release, increment the version code consistently in
`pubspec.yaml`, Dart `ModelProfile.build`, native `ReleaseHardware.BUILD`, and
`scripts/verify_unified_artifact.py`. The last committed Internal testing code is 19; future uploads must use a newer code. The API also rejects reused
version codes that are not visible in the edit's current bundle/APK list.

This is an on-demand local workflow, not a scheduled service or installed CI
trigger. Once credentials and the existing upload key are available, Codex can
run it when asked to upload the latest Internal testing build.
