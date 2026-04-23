# Phase Completion Checklists

## Phase 1: Project Scaffold & Architecture Validation

- [x] Project scaffold created.
- [x] Folder structure established (`lib/kernel/`, `lib/shell/`, `lib/spokes/mock/`).
- [x] Package boundaries and architecture rules wired up (`test/architecture_test.dart`).
- [x] Deliberate violations test created to prove rules work (`test/deliberate_violations_test.dart`).
- [x] Build flavors configured (`dev` and `prod`).

## Phase 2: Kernel Vault & Auth

- [x] Vault dependencies added and approved.
- [x] Vault Service created with `sqflite_sqlcipher` and correct v0 schema.
- [x] Secure Keystore integration via `flutter_secure_storage` to manage device secret.
- [x] Key Derivation via `pointycastle`'s Argon2id generator is implemented and tested.
- [x] `AuthBloc` implemented with state machine for Passphrase and Biometric workflows.
- [x] Debug Vault screen created to allow developer to initialize and test the encrypted vault.

## Phase 3: Hub Dashboard & Shell Routing

- [x] `go_router` dependency added and approved.
- [x] `SpokeContext` and `SpokeModule` contracts established.
- [x] `MockSpoke` refactored to implement `SpokeModule`.
- [x] `DashboardScreen` created.
- [x] `ShellLayout` with `NavigationBar` implemented using `StatefulNavigationShell`.
- [x] `AppRouter` integrated with `AuthBloc` for seamless redirection.

## Phase 4: SpokeModule Contract & Integration

- [x] `SpokeModule` contract, registry, and kernel context fully defined.
- [x] Mock spoke shell integration completed.
- [x] Spoke workspace visibility correctly filtered by ACL.

## Phase 5: Inference & Audio Platform Channels

- [x] `kraken.kernel/inference` and `kraken.kernel/audio` platform channels defined.
- [x] Native stub implementations added to Android (Kotlin) to simulate realistic streaming delays.
- [x] Test UI integrated to verify channel connectivity.

## Phase 6: Inference State Machine

- [x] `LocalInferenceService` built to handle Uninitialized -> Loading -> Warm -> Generating states.
- [x] `InferenceBloc` created to expose reactive state to UI via `emit.forEach`.
- [x] Test inference from debug screen/dashboard works end-to-end on stub.

## Phase 7: User-Facing Terminology Rename

- [x] Create inventory of user-facing strings containing "workspace".
- [x] Update strings in `lib/shell/ui/dashboard_screen.dart` ("Workspace" to "Library").
- [x] Update strings in `lib/shell/ui/workspace_detail_screen.dart` ("Workspace" to "Library").
- [x] Verify "spoke output" terminology does not appear in user-facing contexts.
- [x] Add terminology clarification to `KRAKEN_SECURITY_PROTOCOL.md`.
## Phase 8: Device Test Fixes

- [x] Restored "Skip" option on the onboarding demo screen with equal visual weight.
- [x] Implemented event category classification for audit logs in `VaultService`.
- [x] Refactored `WorkspaceService` to categorize user actions as `user_visible`.
- [x] Replaced raw audit log feed with `RecentActivityCard` to show top 5 user-facing events on Dashboard.
- [x] Resolved "BOTTOM OVERFLOWED" layout rendering bug on the Mock Spoke cards.
- [x] Audited and removed internal snake_case identifiers from user-visible surfaces.
- [x] Updated architecture test suite to enforce clean UI string compliance.
- [x] Adjusted library selector layout and updated AI engine banner copy.
- [x] Fixed conditional rendering of Mock Spoke for release builds.
