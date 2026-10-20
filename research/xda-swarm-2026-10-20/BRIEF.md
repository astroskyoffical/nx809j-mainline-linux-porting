# Mr Handy task: XDA classification ledger (2026-10-20)

**Goal.** Turn the saved XDA forum archive into one auditable ledger of facts that matter for
classifying RedMagic 11 Pro (NX809J) partitions and choosing tools: what is universal, what is
device-unique (IMEI, fingerprint, keys), how backups/EDL dumps were made and failed, and which tool
versions and firmware sources are current.

**Inputs (read-only).**
- `research/xda-swarm-2026-10-20/slices/slice-01.txt` … `slice-10.txt`: the whole archive (3,551 posts,
  chronological). Each post starts `=== POST <id> | thread <id> | <author> | <date> | <permalink>`.
  Lines starting `[QUOTED, not the author's words]` are quotes of someone else: never attribute them
  to the post author.
- `research/xda-swarm-2026-10-20/findings-slices-01-10-except-06-09.json`: 1,355 findings already
  extracted from slices 01–05, 07, 08 and 10 by another team (fields: post_id, author, date,
  device_as_stated, firmware_as_stated, topic, kind, claim, partitions, tools_or_links).
- `research/xda.sqlite3` (table `posts`, columns post_id, author, posted_at, permalink, author_text):
  use it to verify post IDs.
- Context only: `docs/partition-classification.md`, `research/findings.md`, `research/latest-xda.md`, `AGENTS.md`.

**Steps.**
1. Slices **06** and **09** were not extracted (the earlier readers ran out of output space). Extract
   them with the same fields and topics, splitting each slice between helpers by post range so no
   single helper has to return too much. Topics: imei-radio, fingerprint-keys-attestation,
   device-unique-partition, universal-or-variant-firmware, backup-dump, storage-sku-gpt,
   tool-version-or-source, brick-or-recovery, other-relevant. Skip thanks, me-too and chatter.
2. Merge all findings into one list, de-duplicate identical claims from the same post, and spot-check
   at least 30 random findings against the post text in the slices; fix or drop any that misstate
   the post.
3. Write the ledger (see Owns) in plain English: one section per topic. Within each section, group
   related claims, and for each claim give the post ID with its permalink, the author, the date, and
   the device and firmware *as stated*. Mark **conflicts** explicitly (who says what). Separate first-hand
   results from advice and questions. Summarize in your own words; quote at most a short phrase.
   **Never present a forum command as a recipe**: describe what was done, not how to type it.
4. End the ledger with "Proposed updates to docs/partition-classification.md": a bullet list of
   concrete changes the evidence supports (with post IDs). Do **not** edit that file.

**Owns (the only files you may create or change).**
- `research/xda-classification-ledger.md`
- `research/xda-swarm-2026-10-20/findings-all.json`
- `research/xda-swarm-2026-10-20/slice-06-09-findings.json`

**Done when.**
- `findings-all.json` is valid JSON and you report the finding count per slice (all 10 slices present).
- A Python check confirms every post ID cited in the ledger exists in `research/xda.sqlite3`
  (report counts: cited, found, missing; missing must be 0).
- The ledger has all topic sections and the proposed-updates list.

No phone access, no network access, no git commits.
