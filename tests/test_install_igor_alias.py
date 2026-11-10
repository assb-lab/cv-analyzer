"""Test installer file handling without invoking Finder or the user's Igor folder."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "install_igor_alias.sh"
VERSION = re.search(r"^// Semantic version: (\d+\.\d+\.\d+)\b",
                    (ROOT / "CVAnalyzer.ipf").read_text(), re.MULTILINE).group(1)
CURRENT_NAME = "CVAnalyzer_v_" + VERSION.replace(".", "_") + ".ipf"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cva-alias-test-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.dest = base / "Igor Procedures 日本語"
        self.dest.mkdir()
        bin_dir = base / "bin"
        bin_dir.mkdir()
        self.stub(bin_dir / "uname", "#!/bin/bash\nprintf 'Darwin\\n'\n")
        self.stub(
            bin_dir / "osascript",
            "#!/bin/bash\ncat >/dev/null\n"
            'if [[ "${CVA_TEST_FAIL:-0}" == 1 ]]; then exit 1; fi\n'
            'printf new-alias > "$3/$4"\n',
        )
        self.env = os.environ.copy()
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]
        self.env["CVA_IGOR_PROCEDURES_DIR"] = str(self.dest)

    @staticmethod
    def stub(path, text):
        path.write_text(text)
        path.chmod(0o755)

    def invoke(self, fail=False):
        env = self.env.copy()
        env["CVA_TEST_FAIL"] = "1" if fail else "0"
        return subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_replaces_current_and_removes_only_versioned_files(self):
        current = self.dest / CURRENT_NAME
        previous = self.dest / "CVAnalyzer_v_999_123_42.ipf"
        broken = self.dest / "CVAnalyzer_v_999_123_43.ipf"
        unrelated = self.dest / "CVAnalyzer_v_notes.ipf"
        other_tool = self.dest / "uv_vis_analyzer_v_0_0_1.ipf"
        folder = self.dest / "CVAnalyzer_v_7_0_0.ipf"
        current.write_text("previous current")
        previous.write_text("previous version")
        broken.symlink_to("missing-target")
        unrelated.write_text("keep")
        other_tool.write_text("keep")
        folder.mkdir()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(current.read_text(), "new-alias")
        self.assertFalse(previous.exists())
        self.assertFalse(broken.is_symlink())
        self.assertEqual(unrelated.read_text(), "keep")
        self.assertEqual(other_tool.read_text(), "keep")
        self.assertTrue(folder.is_dir())
        self.assertEqual(list(self.dest.glob(".cva-alias.*")), [])
        self.assertEqual(self.invoke().returncode, 0)

    def test_finder_failure_preserves_existing_entries(self):
        current = self.dest / CURRENT_NAME
        previous = self.dest / "CVAnalyzer_v_999_123_42.ipf"
        current.write_text("current")
        previous.write_text("previous")
        result = self.invoke(fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(current.read_text(), "current")
        self.assertEqual(previous.read_text(), "previous")
        self.assertEqual(list(self.dest.glob(".cva-alias.*")), [])

    def test_missing_directory_and_target_directory_are_rejected(self):
        self.env["CVA_IGOR_PROCEDURES_DIR"] = str(self.dest / "missing")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.env["CVA_IGOR_PROCEDURES_DIR"] = str(self.dest)
        target = self.dest / CURRENT_NAME
        target.mkdir()
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertTrue(target.is_dir())


if __name__ == "__main__":
    unittest.main()
