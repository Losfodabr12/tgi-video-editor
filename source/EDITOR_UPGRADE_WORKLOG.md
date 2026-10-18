# Editor upgrade — 2026-10-08

User authorized implementation of: range exports, project version history,
audio meters/voice leveling/music ducking, personal style presets, portable
project collection, optional hardware encoding, more text fonts. Also fix
caption persistence, chroma preview mismatch and slow fallback preview.
Scope: video editor and shared services needed by it. Preserve existing changes.

Baseline: 1.4.25+32, dirty worktree. Backup before edits:
../backups/editor_before_upgrade_20261008_091115.zip.
245 editor tests + FFmpeg integration passed; focused analyze passed.
Temporary diagnostic demonstrated captions stop being exportable after reload.

Implementation checklist:
- [x] Caption identity persisted in Clip; manual conversion for old texts.
- [x] 13 bundled OFL fonts with matching preview/export files.
- [x] Export range + I/O markers and validation.
- [x] Project history + restore + portable project collection.
- [x] Personal text/color/animation presets, including concurrent-save protection.
- [x] Audio measurement, leveling and editable ducking envelopes.
- [x] Hardware encoder probe + software fallback + cancellation tests.
- [x] GPU chroma preview and adaptive fallback capture.
- [x] Tests, Windows build, packaged local release, handoff.

No publication or Store submission requested. No source commit yet.

Validation completed:
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true`:
  477 passed, one pre-existing external test skipped.
- Actual range export checked duration, audio tones and title visibility before,
  during and after its timeline interval, on CPU and NVIDIA NVENC.
- Automatic encoder successfully selected the local NVIDIA RTX 3050. The probe
  uses 640x360 because this device rejected a 128x128 frame.
- All 13 bundled fonts rendered accented text through the actual export service.
- Shader pixel test covered green and neutral key colors, keeping other colors.
- Hardware failure, unavailable hardware and cancellation during probe startup
  preserve the existing destination and clean up temporary export files.
- Short 320x180 test timings (535 ms CPU, 1510 ms NVIDIA including probe) are
  functional checks, not a representative performance benchmark.
- `flutter build windows --release --dart-define=TGI_STORE_BUILD=true
  --dart-define=TGI_APP_VERSION=1.4.26+33`: successful (63.4 seconds).
- Local release: `../releases/tgiapp_editor_1.4.26+33_2026-10-08/`.
- Desktop shortcut: `TGI APP - Editor atualizado.lnk`.
- Packaged startup remained responsive with no stderr errors; packaged FFmpeg
  successfully encoded an NVIDIA test frame. All 13 font assets and the compiled
  chroma shader were present. Native video playback was not manually exercised.
- User guide: `EDITOR_NOVIDADES_1.4.26.md`, also included in the release.

Limitations:
- Audio meter is an estimate from source peak/RMS samples, clip/track gains and
  fades; it is not a post-effects true-peak or LUFS meter.
- Voice leveling sets static clip gain (up to the editor's 200% limit). It does
  not remove all dynamics or replace mastering/compression.
- Ducking detects activity on the selected voice track; music/noise on that
  track can trigger it. The resulting keyframes are editable and undoable.
- Intel/AMD encoder paths have CPU fallback coverage, but no local hardware
  validation. Android/iOS builds were not requested or validated in this task.
- BGRA fallback remains a compatibility path with adaptive frame rate; it is
  not guaranteed to run at native video frame rate.
