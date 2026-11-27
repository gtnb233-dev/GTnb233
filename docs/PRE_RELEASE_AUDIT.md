# Survey Pro Pre-Release Audit Report

**Baseline:** Survey Pro v1.0.0, with v1.1.0 changes recorded below.

**Audit scope:** Dead code, bundled fonts, Rust FFI, native channels and permissions, dependency licenses, and dependency scan status.

## v1.1.0 follow-up

- Android requests Bluetooth connection permission when the user selects a paired GNSS receiver. Legacy Bluetooth permission is limited to Android 11 and earlier. The release manifest requires neither Bluetooth scanning nor Internet access.
- Live sampling accepts a recent GGA sentence from the selected receiver. Both platforms support explicit clipboard input. Sampling never inserts simulated coordinates into field data.
- The Rust DXF writer has a layer and coordinate-order regression. The Dart and Flutter suites include GGA parsing, invalid input, import preview, resection handoff and draft snapshot coverage.

---

## 1. Dead Code & Font Verification Summary

### 1.1 Dead Code Cleanup
- Removed the unused `app/lib/ui/widgets/push_aside_drawer.dart` after checking its references. The workspace shell owns the active sidebar.

### 1.2 Font & Asset Verification
Inspected `app/assets/` and `app/pubspec.yaml`:
- `app/assets/fonts/survey/NotoSansSC.ttf` (1,233,156 bytes) — bundled with `NotoSansSC-OFL.txt` (SIL Open Font License 1.1).
- `app/assets/fonts/survey/JetBrainsMono.ttf` (187,208 bytes) — bundled with `JetBrainsMono-OFL.txt` (SIL Open Font License 1.1).
- No proprietary, unlicensed, or unused font/asset files exist in `app/assets/` or `app/pubspec.yaml`.

---

## 2. Rust FFI & Native MethodChannel / Permission Audit

### 2.1 Rust FFI (`rust/survey_rust_core/src/lib.rs`)
Reviewed eight exported `extern "C"` symbols:
- `survey_rust_abi_version`
- `survey_traverse_distribute`
- `survey_leveling_check`
- `survey_dxf_count_entities`
- `survey_tin_compute_volume`
- `survey_spatial_nearest_2d`
- `survey_dxf_parse_json`
- `survey_string_free`

**Changes included in this build:**

- Pointer-taking entry points guard against null pointers, and array entry points also check zero counts before accessing buffers. Callers must still satisfy each function's buffer and pointer contract.
- FFI entry points that process native buffers catch unwinding Rust panics. Traverse, leveling and TIN buffer element counts use checked multiplication for 32-bit targets. Nearest-neighbour index conversion uses `i32::try_from`.
- TIN skips out-of-bounds, degenerate and non-finite triangle input. The Rust tests cover null and empty FFI inputs and invalid TIN triangles.

### 2.2 Android Permissions & MethodChannels
- **`app/android/app/src/main/AndroidManifest.xml`:**
  - Only declares `android.permission.WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="28"` (for legacy MediaStore save). No redundant or sensitive permissions (`INTERNET`, `CAMERA`, `LOCATION`, etc.).
- **`app/android/app/src/main/kotlin/cn/survey/survey_pro/MainActivity.kt`:**
  - `survey/theme`: `accentColor`, `setKeepScreenOn` (Boolean argument with safe fallback).
  - `survey/files`: `savePngToGallery`, `shareImageUri`. No unused debug/test channels.
  - **Hardening Applied:**
    - Sanitized `filename` (stripped path separators `/`, `\`, and `.`/`..` traversal) and `album` (stripped `..` and leading/trailing slashes) in `savePngToGallery`.
    - Enforced `uri.scheme == "content"` in `shareContentUri` to reject non-content URIs (`file://`, etc.).

### 2.3 Windows Runner (`app/windows/runner/`)
- **`flutter_window.cpp`:**
  - `survey/theme`: `accentColor`, `setWindowBrightness`, `setWindowTitle`, `windowMinimize`, `windowMaximizeToggle`, `windowIsMaximized`, `windowClose`, `windowStartDrag`, `setKeepScreenOn` — matches `NativeWindowBridge` in `app/lib/platform/native_bridge_contract.dart` 1:1.
  - `survey/files`: `pickSaveFile`, `pickOpenFile` — matches `NativeFilesBridge` 1:1. `ShowNativeFileDialog` validates argument types via `std::get_if`, strips leading dots from extensions, and clamps `suggestedName` to `file_buf.size() - 1` (4095).
- **`main.cpp`:** Clean Win32 entry point; no debug/test channels.

---

## 3. Dependency License Inventory

**Result:** **0 GPL / AGPL / copyleft-restricted dependencies** in either Dart (`app/pubspec.lock`) or Rust (`rust/survey_rust_core/Cargo.lock`).

### 3.1 Dart Packages (`app/pubspec.lock`, verified against `%LOCALAPPDATA%\Pub\Cache\hosted`)

| Package | Version | Dependency | License |
|---|---|---|---|
| `async` | 2.13.1 | transitive | BSD-3-Clause |
| `boolean_selector` | 2.1.2 | transitive | BSD-3-Clause |
| `characters` | 1.4.0 | transitive | BSD-3-Clause |
| `clock` | 1.1.2 | transitive | Apache-2.0 |
| `collection` | 1.19.1 | transitive | BSD-3-Clause |
| `csv` | 6.0.0 | direct main | MIT |
| `fake_async` | 1.3.3 | transitive | Apache-2.0 |
| `ffi` | 2.2.0 | direct main | BSD-3-Clause |
| `file` | 7.0.1 | transitive | BSD-3-Clause |
| `flutter` | 0.0.0 | direct main | SDK (BSD-3-Clause) |
| `flutter_lints` | 5.0.0 | direct dev | BSD-3-Clause |
| `flutter_localizations` | 0.0.0 | direct main | SDK (BSD-3-Clause) |
| `flutter_test` | 0.0.0 | direct dev | SDK (BSD-3-Clause) |
| `flutter_web_plugins` | 0.0.0 | transitive | SDK (BSD-3-Clause) |
| `intl` | 0.20.2 | transitive | BSD-3-Clause |
| `leak_tracker` | 11.0.2 | transitive | BSD-3-Clause |
| `leak_tracker_flutter_testing` | 3.0.10 | transitive | BSD-3-Clause |
| `leak_tracker_testing` | 3.0.2 | transitive | BSD-3-Clause |
| `lints` | 5.1.1 | transitive | BSD-3-Clause |
| `matcher` | 0.12.17 | transitive | BSD-3-Clause |
| `material_color_utilities` | 0.11.1 | transitive | Apache-2.0 |
| `meta` | 1.16.0 | transitive | BSD-3-Clause |
| `path` | 1.9.1 | transitive | BSD-3-Clause |
| `path_provider_linux` | 2.2.1 | transitive | BSD-3-Clause |
| `path_provider_platform_interface` | 2.1.2 | transitive | BSD-3-Clause |
| `path_provider_windows` | 2.3.0 | transitive | BSD-3-Clause |
| `platform` | 3.1.6 | transitive | BSD-3-Clause |
| `plugin_platform_interface` | 2.1.8 | transitive | BSD-3-Clause |
| `shared_preferences` | 2.5.5 | direct main | BSD-3-Clause |
| `shared_preferences_android` | 2.4.23 | transitive | BSD-3-Clause |
| `shared_preferences_foundation` | 2.5.6 | transitive | BSD-3-Clause |
| `shared_preferences_linux` | 2.4.1 | transitive | BSD-3-Clause |
| `shared_preferences_platform_interface` | 2.4.2 | transitive | BSD-3-Clause |
| `shared_preferences_web` | 2.4.3 | transitive | BSD-3-Clause |
| `shared_preferences_windows` | 2.4.1 | transitive | BSD-3-Clause |
| `sky_engine` | 0.0.0 | transitive | SDK (BSD-3-Clause) |
| `source_span` | 1.10.2 | transitive | BSD-3-Clause |
| `stack_trace` | 1.12.1 | transitive | BSD-3-Clause |
| `stream_channel` | 2.1.4 | transitive | BSD-3-Clause |
| `string_scanner` | 1.4.1 | transitive | BSD-3-Clause |
| `survey_core` | 1.0.0 | direct main (path) | Local workspace |
| `term_glyph` | 1.2.2 | transitive | BSD-3-Clause |
| `test_api` | 0.7.6 | transitive | BSD-3-Clause |
| `vector_math` | 2.2.0 | transitive | BSD-3-Clause |
| `vm_service` | 15.4.0 | transitive | BSD-3-Clause |
| `web` | 1.1.1 | transitive | BSD-3-Clause |
| `xdg_directories` | 1.1.0 | transitive | BSD-3-Clause |

### 3.2 Rust Crates (`rust/survey_rust_core/Cargo.lock`, verified against `%USERPROFILE%\.cargo\registry\src`)

| Crate | Version | License (`Cargo.toml`) |
|---|---|---|
| `survey_rust_core` | 0.1.0 | MIT |
| `itoa` | 1.0.19 | MIT OR Apache-2.0 |
| `memchr` | 2.8.3 | Unlicense OR MIT |
| `proc-macro2` | 1.0.107 | MIT OR Apache-2.0 |
| `quote` | 1.0.47 | MIT OR Apache-2.0 |
| `serde` | 1.0.229 | MIT OR Apache-2.0 |
| `serde_core` | 1.0.229 | MIT OR Apache-2.0 |
| `serde_derive` | 1.0.229 | MIT OR Apache-2.0 |
| `serde_json` | 1.0.154 | MIT OR Apache-2.0 |
| `syn` | 3.0.10 | MIT OR Apache-2.0 |
| `unicode-ident` | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| `zmij` | 1.0.23 | MIT |

---

## 4. Dependency Review and Scan Status

### 4.1 `dart pub outdated` (in `app/`)
- **Direct dependencies:**
  - `csv`: current `6.0.0` (latest `8.0.0`, constrained by `pubspec.yaml` `csv: 6.0.0`)
  - `shared_preferences`: current `2.5.5` (latest `2.5.6`)
- **Dev dependencies:**
  - `flutter_lints`: current `5.0.0` (resolvable/latest `6.0.0`)
- **Transitive highlights:** `characters` (`1.4.0` -> `1.4.1`), `clock` (`1.1.2` -> `1.1.3`), `intl` (`0.20.2` -> `0.20.3`), `material_color_utilities` (`0.11.1` -> `0.13.1`), `meta` (`1.16.0` -> `1.19.0`), `shared_preferences_android` (`2.4.23` -> `2.5.5`), `shared_preferences_foundation` (`2.5.6` -> `2.6.2`), `vector_math` (`2.2.0` -> `2.4.4`), `web` (`1.1.1` -> `1.1.2`).
- Summary from CLI: `2 dependencies are constrained to versions that are older than a resolvable version.`

### 4.2 Rust dependency review
- Automated advisory scan status: pending. `cargo-audit` was unavailable during the original review.
- The lockfile lists one direct registry dependency (`serde_json`) and 11 registry crates in total.
