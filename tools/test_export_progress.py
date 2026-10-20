import unittest

import export_progress


def _item(label, group, state, kind="evidence", evidence=None):
    return {"id": label, "kind": kind, "group": group, "label": label, "scope": label + " scope",
            "state": state, "reason": "", "blockers": [], "evidence": evidence or []}


class ExportProgressTest(unittest.TestCase):
    def setUp(self):
        self.groups = {
            "Boot & recovery": [
                _item("A return", "Boot & recovery", "ready",
                      evidence=[{"path": "docs/recovery.md", "sha256": "ab" * 32}]),
                _item("Temp boot", "Boot & recovery", "pending"),
            ],
            "Platform": [_item("mod%d" % i, "Platform", "pending", kind="module") for i in range(45)],
        }
        self.state = {
            "items": [i for g in self.groups.values() for i in g],
            "backup": {"state": "captured-with-gaps", "current_batch": "53/53", "verified_batches": 44},
            "errors": ["backup: failed capture batches remain unverified"],
            "generated_at": "2026-10-20T00:00:00Z",
        }
        self.milestones = [{"id": "M0", "title": "Recovery gate", "state": "in-progress",
                            "now": "Partial.", "evidence": ["docs/recovery.md"]}]

    def test_markdown_counts_and_squares(self):
        md = export_progress.render_markdown(self.state, self.milestones, self.groups)
        self.assertIn("| 🟩 Verified scopes | **1** |", md)
        self.assertIn("| 🟥 Open scopes | **46** |", md)
        self.assertEqual(md.count("🟩"), 1 + 2)   # one square, legend line and the count row
        self.assertIn("**Platform** · 0 verified / 45", md)
        self.assertIn("[docs/recovery.md](docs/recovery.md) `abababababab`", md)
        self.assertIn("🟡 In progress", md)

    def test_svg_has_one_rect_per_scope(self):
        svg = export_progress.render_svg(self.groups)
        self.assertEqual(svg.count('fill="#2ea043"'), 1)
        self.assertEqual(svg.count('fill="#da3633"'), 46)
        self.assertIn("1 verified / 47", svg)

    def test_timestamp_line_is_ignored_when_checking_freshness(self):
        a = "x\n_Data generated 2026-10-20T00:00:00Z._\n"
        b = "x\n_Data generated 2026-10-21T00:00:00Z._\n"
        self.assertEqual(export_progress._strip_volatile(a), export_progress._strip_volatile(b))


if __name__ == "__main__":
    unittest.main()
