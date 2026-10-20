# ZTE Family Toolbox static-review snapshot

This folder supports [`docs/zte-toolbox-assessment.md`](../../docs/zte-toolbox-assessment.md). It records the retained `1.2.9-beta1` archive and a contained, selected extraction of NX809J profile assets and read/write scripts.

- [`archive-manifest.json`](archive-manifest.json) records archive hashes, the internal version string, extraction tool/version, extraction scope, and scope boundaries.
- [`archive-listing.txt`](archive-listing.txt) is a saved 7-Zip listing of the original archive.
- [`extracted-files.json`](extracted-files.json) records SHA-256 and byte size for every extracted file.
- [`extracted/`](extracted/) contains selected static-analysis inputs only, including `bin/conf/dev.csv`, the NX809J Sahara XML and companion images, `bin/ztetoolbox.bat`, `bin/read.bat`, `bin/write.bat`, partition helpers, the version file, and the bundled English ROM-maker note.

The root archive and its retained backup copy are both 47,724,368 bytes with the same SHA-256 (`550fef1ca2720a5e647bf2132c265fef84a7ac39e1ab4b7dcc6d5ee9fbf003d4`). The internal launcher config also sets `prog_ver=1.2.9-beta1`.

The archive was listed and selected files extracted with 7-Zip 22.01. No toolbox executable, batch file, driver installer, ABL, Sahara/Firehose image, or phone operation was run.
