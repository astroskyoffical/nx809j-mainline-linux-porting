import unittest

from extract_panel_commands import parse_records


def command(packet_type, payload, wait_ms=0):
    return bytes((packet_type, 1, 0, 0, wait_ms)) + len(payload).to_bytes(2, "big") + payload


class PanelCommandParserTests(unittest.TestCase):
    def test_decodes_records_and_rejects_truncated_data(self):
        data = bytes.fromhex(
            "15 01 00 00 00 00 02 fe 00 "
            "05 01 00 00 14 00 01 28"
        )
        records = parse_records(data)
        self.assertEqual(len(records), 2)
        self.assertEqual(records[0]["controller_index"], 0)
        self.assertEqual(records[0]["payload_hex"], "fe 00")
        self.assertEqual(records[1]["post_wait_ms"], 20)
        self.assertEqual(records[1]["dcs_command_name"], "display off")
        self.assertEqual(records[1]["vendor_page"], "0x00")
        for malformed in (data[:-1], data[:6], b""):
            with self.assertRaises(ValueError):
                parse_records(malformed)

    def test_nonzero_page_to_user_page_transition(self):
        data = b"".join(
            (
                command(0x15, bytes.fromhex("fe d2")),
                command(0x15, bytes.fromhex("51 08")),
                command(0x15, bytes.fromhex("fe 00")),
                command(0x05, bytes.fromhex("11")),
                command(0x05, bytes.fromhex("29")),
            )
        )
        records = parse_records(data)
        self.assertEqual([r["vendor_page"] for r in records], ["0xd2", "0xd2", "0x00", "0x00", "0x00"])
        self.assertEqual([r["dcs_command_name"] for r in records], ["", "", "", "sleep out", "display on"])

    def test_page_context_resets_for_each_table(self):
        first = parse_records(command(0x15, bytes.fromhex("fe 5b")))
        second = parse_records(command(0x15, bytes.fromhex("11 02")))
        self.assertEqual(first[0]["vendor_page"], "0x5b")
        self.assertEqual(second[0]["vendor_page"], "")
        self.assertEqual(second[0]["dcs_command_name"], "")

    def test_unrecognized_fe_payload_makes_page_unknown(self):
        data = b"".join(
            (
                command(0x15, bytes.fromhex("fe 00")),
                command(0x39, bytes.fromhex("fe 00 01")),
                command(0x15, bytes.fromhex("11 02")),
            )
        )
        records = parse_records(data)
        self.assertEqual([r["vendor_page"] for r in records], ["0x00", "", ""])
        self.assertEqual(records[-1]["dcs_command_name"], "")


if __name__ == "__main__":
    unittest.main()
