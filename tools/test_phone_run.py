import unittest

import phone_run


class PhoneRunTest(unittest.TestCase):
    def test_commands_contain_no_script_text(self):
        cmds = phone_run.build_commands("adb", "SER", "/data/local/tmp/claude-run-0123456789abcdef.sh", ["a1", "--x=2"])
        self.assertEqual(cmds["upload"], ["adb", "-s", "SER", "exec-in", "su", "-c",
                                          "cat > /data/local/tmp/claude-run-0123456789abcdef.sh"])
        self.assertEqual(cmds["run"][-1], "sh /data/local/tmp/claude-run-0123456789abcdef.sh a1 --x=2")
        self.assertEqual(cmds["remove"][-1], "rm -f /data/local/tmp/claude-run-0123456789abcdef.sh")

    def test_rejects_arguments_that_would_need_quoting(self):
        for bad in ["a b", "x;y", "$(id)", "it's", 'q"', "a|b", "a&b"]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                phone_run.build_commands("adb", "SER", "/data/local/tmp/x.sh", [bad])

    def test_remote_names_are_private_and_unique(self):
        names = {phone_run.remote_name() for _ in range(50)}
        self.assertEqual(len(names), 50)
        for n in names:
            self.assertRegex(n, r"^/data/local/tmp/claude-run-[0-9a-f]{16}\.sh$")


if __name__ == "__main__":
    unittest.main()
