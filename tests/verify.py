#!/usr/bin/env python3
"""Exercise command success/failure without changing the test Mac's power state."""
import os
from pathlib import Path
import plistlib
import subprocess
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Scripts(unittest.TestCase):
    def run_script(self, mode, failure=""):
        with tempfile.TemporaryDirectory(prefix="mac awake tests ") as temporary:
            folder = Path(temporary)
            mock = folder / "power-mock"
            mock.write_text('''#!/bin/zsh
set -eu
print -r -- "$*" >> "$TEST_LOG"
case "$*" in
    '-a disablesleep 1'|'-a disablesleep 0')
        [[ "$TEST_FAILURE" != authorization ]] || exit 1
        print "$3" > "$TEST_STATE" ;;
    '-g')
        [[ "$TEST_FAILURE" != read ]] || exit 1
        print 'System-wide power settings:'
        if [[ "$TEST_FAILURE" == verification ]]; then print ' SleepDisabled 2'
        else print " SleepDisabled $(cat "$TEST_STATE")"; fi ;;
    displaysleepnow) [[ "$TEST_FAILURE" != display ]] || exit 1 ;;
    *) exit 99 ;;
esac
''')
            mock.chmod(0o755)
            source = (ROOT / f"scripts/Keep-Mac-Awake-{mode}.command").read_text()
            source = source.replace("/usr/bin/sudo ", "")
            source = source.replace("/usr/bin/pmset", '"' + str(mock) + '"')
            source = source.replace("/bin/sleep 5", ":")
            script = folder / "script.command"
            script.write_text(source)
            env = dict(os.environ, TEST_LOG=str(folder / "calls"),
                       TEST_STATE=str(folder / "state"), TEST_FAILURE=failure)
            result = subprocess.run(["/bin/zsh", str(script)], env=env, capture_output=True, text=True)
            return result, (folder / "calls").read_text().splitlines()

    def test_on_preserves_timers_and_blanks_display(self):
        result, calls = self.run_script("ON")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["-a disablesleep 1", "-g", "displaysleepnow"])

    def test_off_only_restores_sleep_eligibility(self):
        result, calls = self.run_script("OFF")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["-a disablesleep 0", "-g"])

    def test_failed_authorization_stops_immediately(self):
        for mode in ["ON", "OFF"]:
            result, calls = self.run_script(mode, "authorization")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(calls), 1)

    def test_failed_read_or_verification_never_blanks_display(self):
        for mode in ["ON", "OFF"]:
            for failure in ["read", "verification"]:
                result, calls = self.run_script(mode, failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("displaysleepnow", calls)

    def test_display_failure_reports_enabled_state(self):
        result, _ = self.run_script("ON", "display")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Keep-awake is enabled, but the display-off request failed", result.stderr)

    def test_portable_shortcuts_match_command_scripts(self):
        for mode in ["On", "Off"]:
            workflow = plistlib.loads((ROOT / f"Shortcuts/Keep Mac Awake {mode}.plist").read_bytes())
            actions = workflow["WFWorkflowActions"]
            self.assertEqual(len(actions), 2)
            parameters = actions[0]["WFWorkflowActionParameters"]
            self.assertTrue(parameters["RunAsRoot"])
            self.assertEqual(parameters["Shell"], "/bin/zsh")
            self.assertEqual(parameters["Script"], (ROOT / f"scripts/Keep-Mac-Awake-{mode.upper()}.command").read_text())
            self.assertNotIn("/Users/", parameters["Script"])
            self.assertTrue((ROOT / f"Shortcuts/Keep Mac Awake {mode}.shortcut").read_bytes().startswith(b"AEA1"))

    def test_signed_payloads_match_readable_sources(self):
        for mode in ["On", "Off"]:
            signed = ROOT / f"Shortcuts/Keep Mac Awake {mode}.shortcut"
            data = signed.read_bytes()
            size = struct.unpack("<I", data[8:12])[0]
            certificate = plistlib.loads(data[12:12 + size])["SigningCertificateChain"][0]
            with tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                (folder / "certificate.der").write_bytes(certificate)
                public_key = subprocess.check_output(["/usr/bin/openssl", "x509", "-inform", "DER", "-in",
                                                      str(folder / "certificate.der"), "-pubkey", "-noout"])
                (folder / "public.pem").write_bytes(public_key)
                subprocess.run(["/usr/bin/aea", "decrypt", "-i", str(signed), "-o", str(folder / "archive"),
                                "-sign-pub", str(folder / "public.pem")], check=True, capture_output=True)
                subprocess.run(["/usr/bin/aa", "extract", "-i", str(folder / "archive"),
                                "-d", str(folder / "contents")], check=True, capture_output=True)
                actual = plistlib.loads((folder / "contents/Shortcut.wflow").read_bytes())
                expected = plistlib.loads((ROOT / f"Shortcuts/Keep Mac Awake {mode}.plist").read_bytes())
                self.assertEqual(actual["WFWorkflowActions"], expected["WFWorkflowActions"])


if __name__ == "__main__":
    unittest.main()
