# AVFoundation / FFmpeg parity investigation

Validated 2026-10-30 with:

```sh
swift build
.build/debug/test-hash /Volumes/Ext-6TB-2/HashTestVids 8
```

The folder contained **six videos** during this investigation. The V1–V6 files mentioned in earlier logs were no longer in this input directory and are not covered by the final result.

## Result

- Before: 4/6 exact PHash matches; two videos differed by 2 bits.
- After: **6/6 exact PHash matches**, all six distances zero.
- **150/150 selected frame timestamps identical** across backends.
- All 150 final FFmpeg BMPs are byte-identical to the saved baseline FFmpeg BMPs.
- AVFoundation remains independent of FFmpeg: it neither loads the reference reports nor invokes FFmpeg to select frames.
- This establishes hash parity for this corpus, **not pixel equality or universal backend parity**. Final mean absolute RGB differences range from 3.65 to 6.89 levels / 255.

See `summary.json` for hashes, individual metrics, the baseline/final run identifiers, and absolute paths to each output folder. `final.log` contains the final end-to-end command output.

## Controlled experiments

| Experiment | Exact hashes | Selected timestamps matching FFmpeg |
|---|---:|---:|
| Original native sampling + sRGB | 4/6 | 0/150 |
| Replay FFmpeg timestamps + sRGB | 5/6 | 150/150 |
| Replay FFmpeg timestamps + source RGB colour space | 6/6 | 150/150 |
| Native rounded duration / next constant-rate boundary + source RGB | 6/6 | 150/150 |
| Native sample cursor + source RGB | 6/6 | 150/150 |
| Integrated native sample cursor, with edit mapping + source RGB | 6/6 | 150/150 |

The constant-rate arithmetic experiment was **not** put into production. The integrated sampler reads real presentation timestamps using AVSampleCursor, including variable-rate gaps.

The image generator returns `kCGColorSpaceCoreMedia709` for these sources. Drawing into an sRGB context altered the transfer response. Preserving the tagged RGB space reduced the brightness bias and removed the remaining hash mismatch once frames were aligned. This does not make Apple's decoder/resizer pixel-identical to libswscale.

## Implementation

1. Native assets request precise duration and timing. Sampling duration is rounded to centiseconds to approach the FFmpeg duration used by the existing sampling policy.
2. Sampling instants are represented at microsecond precision, matching FFmpeg's seek argument precision.
3. A sample cursor finds the first real presentation frame at or after the instant. Source/target segment mappings translate between media timestamps and the edited asset timeline. The selected rational CMTime is passed directly to `image(at:)`, avoiding 1/600 quantization.
4. RGB rendering preserves the source's RGB colour space. Untagged or non-RGB images retain the sRGB fallback.
5. The rest of sprite composition, resizing, grayscale, DCT and hash thresholding is unchanged.

Two configuration properties allow comparison with the prior native behavior:

```swift
var configuration = HashConfiguration.Avfoundation
configuration.avFoundationAlignsFrameSelection = false
configuration.avFoundationPreservesSourceColorSpace = false
```

Both properties default to true and affect only native extraction. When the media format cannot provide sample cursors/mappings, native extraction logs a warning and falls back to ordinary image requests. No generic claim of parity is made for unsupported cursors, different container-duration interpretations, HDR tone mapping, other colour spaces, different track selection, or every possible edit layout.

The timestamp CSV now includes `planned_seconds`, the sampling instant before choosing a real frame. `requested_seconds` is the selected timestamp submitted to `image(at:)`. Consequently FFmpeg's original request and the native request can differ while **actual** frame timestamps match exactly; this is intentional.

Diagnostic folders under `temp/` contain the source filename, date/time, a short unique token, and `-avf` or `-ffmpg`. The token prevents simultaneous requests for the same basename from overwriting each other.

## Validation

```sh
VIDEOHASH_RUN_MEDIA_TESTS=1 swift test --filter \
  'AVFoundationFrameSamplerTests|RGBImageColorTests|PHashReferenceParityTests|FrameExtractionFallbackTests|FrameExtractionCancellationTests'
```

12 tests across five suites passed (parameterized cases included). The generated media tests exercise constant rate, variable-rate gaps, MP4 edit offsets, exact image-generator timestamps, and complete native hashing with an intentionally nonexistent FFmpeg path. A follow-up run of the native-only tests passed after adding that independence check. See `tests2.log` and `native-only-tests.log`.

The original cancellation fixture had a readiness-file race; it now publishes its ready marker atomically. The output-directory UUID token also fixes collisions found by simultaneously running fallback fixtures with identical source basenames.

The full test suite was not run. Original input videos were not modified.

## Replaying the original experiments

`experiment.swift` is a standalone diagnostic harness, not the production sampler. It uses the library's actual sprite/DCT/hash implementation and records output BMPs plus JSON metrics. The initial cursor experiment assumes identity edit mappings; the production sampler and tests handle edit mappings explicitly.

For this machine's SwiftPM Xcode build-system layout:

```sh
swiftc -O -parse-as-library -I .build/debug \
  Benchmarks/avfoundation-parity/experiment.swift \
  .build/debug/VideoHash.o .build/debug/Logging.o \
  -o /tmp/videohash-parity-experiment

/tmp/videohash-parity-experiment \
  95E98074-A31D-4E88-9F45-7DF07FF9AFF9 \
  thumb_srgb,thumb_source \
  /tmp/aligned-color.json
```

The saved reference run must still exist under `temp/`. `aligned-color.json`, `native-selection.json` and `native-cursor.json` contain the original measurements.
