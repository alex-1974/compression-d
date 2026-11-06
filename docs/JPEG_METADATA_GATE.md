# JPEG neutral colour-metadata gate

The metadata-only API is `inspectJpegColorMetadata`. It reports bounded JPEG
frame, JFIF, Adobe, ICC and EXIF facts using explicit `MetadataState` values.
It never decodes pixels, performs colour conversion, upsamples chroma or applies
EXIF orientation.

Implemented and verified:

- neutral source-model and bit-depth facts;
- provenance flags for frame/JFIF/Adobe/ICC/EXIF;
- bounded ICC header and tag-table validation;
- recognition of RGB/GRAY ICC colour spaces;
- recognition of complete RGB matrix/TRC tag groups;
- explicit unsupported/conflicting states;
- malformed input and file-size limits;
- DMD/LDC unit-test coverage.

The API intentionally does not claim BT.601/BT.709/sRGB from incomplete
metadata. Full ICC numeric tag interpretation and an external imageio-d
consumer mapping remain integration work outside this repository's current
codec-only test surface.
