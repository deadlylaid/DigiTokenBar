import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_metadata", ROOT / "scripts/release-metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)

NOTES = """## New

**New feature** (#123, @Alice) — works offline.

## Fixed

- A bug is fixed (#124, @Bob).

## Other

None.

## Contributors

@Alice · @Bob

Thank you all.

---

**Install:** download `DigiTokenBar.zip` below and move the app to Applications. On first open click **Open Anyway** in System Settings › Privacy & Security, or run `xattr -dr com.apple.quarantine /Applications/DigiTokenBar.app`.

**Upgrade:** replace the app with the one in the new `DigiTokenBar.zip`.
"""


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.notes = self.root / "notes.md"
        self.notes.write_text(NOTES)
        self.roster = self.root / "contributors.txt"
        self.roster.write_text("alice\n@bob\n")

    def check(self):
        metadata.check_notes(str(self.notes), str(self.roster))

    def test_valid_notes_are_not_rewritten(self):
        self.check()
        self.assertEqual(self.notes.read_text(), NOTES)

    def test_missing_or_empty_notes_fail(self):
        for value in ("", str(self.root / "missing")):
            with self.assertRaises(ValueError):
                metadata.check_notes(value, str(self.roster))
        self.notes.write_text("")
        with self.assertRaises(ValueError):
            self.check()

    def test_all_sections_and_install_instructions_are_required(self):
        for value in ("## New", "## Fixed", "## Other", "## Contributors", "**Install:**", "`DigiTokenBar.zip`",
                      "Open Anyway", "xattr -dr com.apple.quarantine /Applications/DigiTokenBar.app", "**Upgrade:**"):
            with self.subTest(value=value):
                self.notes.write_text(NOTES.replace(value, "removed"))
                with self.assertRaises(ValueError):
                    self.check()

    def test_homebrew_instructions_are_rejected(self):
        # DigiTokenBar has no cask; the upstream lines would install PokeTokenBar instead.
        for line in ("brew install --cask chattymin/tap/poke-token-bar", "brew upgrade --cask poke-token-bar"):
            with self.subTest(line=line):
                self.notes.write_text(NOTES + "\n" + line + "\n")
                with self.assertRaisesRegex(ValueError, "Homebrew"):
                    self.check()

    def test_template_install_lines_pass_the_check(self):
        # The fixed Install/Upgrade lines in the template are exactly what the checker asks for.
        template = (ROOT / "docs/reference/release-notes-template.md").read_text()
        tail = template.split("\n---\n", 1)[1]
        self.notes.write_text(NOTES.split("\n---\n", 1)[0] + "\n---\n" + tail)
        self.check()

    def test_owner_mention_does_not_require_a_contributor_entry(self):
        self.notes.write_text(NOTES.replace("A bug is fixed (#124, @Bob).", "A bug is fixed (#124, @Bob, @deadlylaid)."))
        self.check()

    def test_unfilled_template_fails(self):
        self.notes.write_text((ROOT / "docs/reference/release-notes-template.md").read_text())
        with self.assertRaises(ValueError):
            self.check()

    def test_roster_member_missing_from_both_summary_and_contributors_fails(self):
        self.roster.write_text("alice\nbob\ncarol\n")
        with self.assertRaisesRegex(ValueError, "@carol"):
            self.check()

    def test_summary_credit_cannot_be_omitted_from_contributors(self):
        self.roster.write_text("alice\n")
        self.notes.write_text(NOTES.replace("@Alice · @Bob", "@Alice"))
        with self.assertRaisesRegex(ValueError, "@bob"):
            self.check()

    def test_no_external_contributors_must_be_explicit(self):
        self.roster.write_text("")
        self.notes.write_text(NOTES.replace(", @Alice", "").replace(", @Bob", "").replace(
            "@Alice · @Bob\n\nThank you all.", "No external contributors in this release."))
        self.check()

    def test_roster_is_required(self):
        with self.assertRaises(ValueError):
            metadata.check_notes(str(self.notes), "")

    def test_bot_credit_does_not_require_a_human_contributor(self):
        self.roster.write_text("")
        self.notes.write_text(NOTES.replace("@Alice", "@dependabot[bot]").replace(", @Bob", "").replace(
            "@dependabot[bot] · @Bob\n\nThank you all.", "No external contributors in this release."))
        self.check()

    def test_default_commit_has_no_fixed_coauthor(self):
        self.assertEqual(metadata.commit_message("2.5.4"), "release: bump version to 2.5.4")

    def test_only_explicit_coauthors_are_preserved(self):
        authors = self.root / "coauthors.txt"
        authors.write_text("Alice <alice@example.com>\nBob <bob@example.com>\nAlice <alice@example.com>\n")
        self.assertEqual(metadata.commit_message("2.5.4", str(authors)),
                         "release: bump version to 2.5.4\n\nCo-Authored-By: Alice <alice@example.com>\nCo-Authored-By: Bob <bob@example.com>")

    def test_invalid_coauthor_fails(self):
        authors = self.root / "coauthors.txt"
        authors.write_text("Co-Authored-By: guessed model")
        with self.assertRaises(ValueError):
            metadata.commit_message("2.5.4", str(authors))

    def test_previous_release_is_ours_not_an_upstream_tag(self):
        # The repository still carries upstream PokeTokenBar's v2.x tags. "Since the last release" must
        # start at DigiTokenBar's own tag, never at an upstream one before the fork point.
        repo = self.root / "repo"
        (repo / "scripts").mkdir(parents=True)
        (repo / "assets").mkdir()
        (repo / "Sources").mkdir()
        (repo / "scripts" / "release.sh").write_text((ROOT / "scripts" / "release.sh").read_text())
        (repo / "assets" / "AppIcon.icns").write_text("icon")
        for name in ("README.md", "README.ko.md", "README.ja.md"):
            (repo / name).write_text("`DigiTokenBar.zip` from https://github.com/deadlylaid/DigiTokenBar/releases/latest\n")
        env = {k: v for k, v in os.environ.items() if not k.startswith(("PTB_", "GIT_"))}
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t",
                   GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")

        def git(*args):
            return subprocess.run(["git", *args], cwd=repo, env=env, check=True,
                                  capture_output=True, text=True).stdout.strip()

        def commit(message, path):
            (repo / path).write_text(message)
            git("add", "-A")
            git("commit", "-q", "-m", message)

        git("init", "-q", "-b", "main")
        commit("feat: upstream feature", "Sources/upstream.swift")
        git("tag", "v2.5.7")
        commit("fix: last upstream commit", "Sources/upstream2.swift")
        env["PTB_FORK_POINT"] = git("rev-parse", "HEAD")
        commit("feat(digimon): first fork feature", "Sources/digimon.swift")

        def check_only():
            return subprocess.run(["bash", "scripts/release.sh", "--check-only"], cwd=repo, env=env,
                                  capture_output=True, text=True).stdout

        first = check_only()
        self.assertIn("첫 릴리스", first)
        self.assertNotIn("v2.5.7", first, "an upstream tag is not our previous release")

        git("tag", "v0.1.0")
        commit("feat(digimon): second fork feature", "Sources/digimon2.swift")
        second = check_only()
        self.assertIn("v0.1.0 이후 새 기능", second)
        self.assertIn("second fork feature", second)
        self.assertNotIn("first fork feature", second)

    def test_release_stops_before_side_effects_when_notes_are_missing(self):
        # Run the real shell entry point inside a disposable fixture. No git writes,
        # network, app build, signing, or installation commands are reachable.
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("release.sh", "release-metadata.py"):
            (scripts / name).write_text((ROOT / "scripts" / name).read_text())
        (scripts / "build-app.sh").write_text('VERSION="2.5.3"\n')
        marker = self.root / "test-gate-reached"
        gate = scripts / "test-gate.sh"
        gate.write_text('#!/bin/sh\ntouch test-gate-reached\nexit 1\n')
        gate.chmod(0o755)
        commands = self.root / "bin"
        commands.mkdir()
        git = commands / "git"
        git.write_text('#!/bin/sh\nif [ "$1" = rev-parse ]; then echo main; else exit 99; fi\n')
        git.chmod(0o755)
        env = {k: v for k, v in os.environ.items() if not k.startswith("PTB_")}
        env["PATH"] = str(commands) + os.pathsep + env["PATH"]
        command = ["bash", str(scripts / "release.sh"), "2.5.4"]
        missing = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("PTB_NOTES_FILE", missing.stderr)
        self.assertFalse(marker.exists())
        env.update(PTB_NOTES_FILE=str(self.notes), PTB_CONTRIBUTORS_FILE=str(self.roster))
        valid = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(valid.returncode, 0, "Fixture intentionally stops at test-gate")
        self.assertTrue(marker.exists())
        self.assertEqual((scripts / "build-app.sh").read_text(), 'VERSION="2.5.3"\n')


if __name__ == "__main__":
    unittest.main()
