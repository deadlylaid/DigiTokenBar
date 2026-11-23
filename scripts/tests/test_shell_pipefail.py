import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# `producer | grep -q pattern` under `set -o pipefail`: grep -q exits at the first match, the producer
# gets SIGPIPE (exit 141) and the whole pipeline fails although the pattern was found. release.sh
# reported a correctly signed v0.1.0 build as unsigned this way. Capture the output, then match.
QUIET_GREP = re.compile(r"\|\s*grep\b[^|;&]*?(\s-[A-Za-z]*q[A-Za-z]*\b|\s--quiet\b)")


def tracked(*patterns):
    out = subprocess.run(["git", "ls-files", *patterns], cwd=ROOT, capture_output=True, text=True, check=True)
    return [ROOT / line for line in out.stdout.splitlines() if line]


def offenders(path, text, always_pipefail=False):
    if not always_pipefail and "pipefail" not in text:
        return []
    return [f"{path.relative_to(ROOT)}:{n}: {line.strip()}"
            for n, line in enumerate(text.splitlines(), 1)
            if not line.lstrip().startswith("#") and QUIET_GREP.search(line)]


class PipefailQuietGrepTests(unittest.TestCase):
    def test_no_quiet_grep_at_the_end_of_a_pipe_under_pipefail(self):
        found = []
        for path in tracked("*.sh"):
            found += offenders(path, path.read_text())
        # GitHub Actions runs bash steps with -eo pipefail.
        for path in tracked(".github/workflows/*.yml", ".github/workflows/*.yaml"):
            found += offenders(path, path.read_text(), always_pipefail=True)
        self.assertEqual([], found)

    def test_the_check_sees_the_pattern_that_broke_the_release(self):
        broken = 'set -euo pipefail\ncodesign -dv "$APP" 2>&1 | grep -qF "Authority=$ID" || exit 1\n'
        self.assertEqual(1, len(offenders(ROOT / "x.sh", broken)))
        self.assertEqual([], offenders(ROOT / "x.sh", broken.replace("set -euo pipefail\n", "")))
        self.assertEqual([], offenders(ROOT / "x.sh", 'set -o pipefail\nif grep -q x file; then :; fi\n'))


if __name__ == "__main__":
    unittest.main()
