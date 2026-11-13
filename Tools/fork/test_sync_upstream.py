#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Jater
"""Checks for Tools/fork/sync_upstream.py's decisions.

    python3 Tools/fork/test_sync_upstream.py
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import sync_upstream as sync

PASSING_SCRIPTS = "\n".join(sync.SCRIPT_TEST_MARKERS)
FLAKY = "jumping to distant selections does not realize the intervening history"


def harness_output(*failures, scripts=PASSING_SCRIPTS):
    lines = ["notch: FAILED (67894 checks, 37.53s)",
             f"TESTS FAILED ({len(failures)} of 122934):"]
    lines += [f"  - Tests/{name}.swift:{line}: {message}" for name, line, message in failures]
    return "\n".join(lines + [scripts])


class EvaluateTests(unittest.TestCase):
    def test_a_clean_run_passes(self):
        self.assertEqual(sync.evaluate_tests(0, PASSING_SCRIPTS, [FLAKY]), ("pass", []))

    def test_only_known_flaky_failures_are_let_through(self):
        verdict, failures = sync.evaluate_tests(1, harness_output(("NotchCompactTests", 339, FLAKY)), [FLAKY])
        self.assertEqual(verdict, "flaky")
        self.assertEqual(failures, [("Tests/NotchCompactTests.swift:339", FLAKY)])

    def test_a_real_failure_beside_a_flaky_one_fails(self):
        output = harness_output(("NotchCompactTests", 339, FLAKY), ("UpdateFeatureTests", 12, "update offered"))
        self.assertEqual(sync.evaluate_tests(1, output, [FLAKY])[0], "fail")

    def test_a_failed_script_test_fails_even_with_only_flaky_swift_failures(self):
        output = harness_output(("NotchCompactTests", 339, FLAKY),
                                scripts="PREFERENCE CLEANUP TESTS OK\nUNINSTALL SPACES TESTS OK")
        self.assertEqual(sync.evaluate_tests(1, output, [FLAKY])[0], "fail")

    def test_a_failure_without_harness_lines_fails(self):
        self.assertEqual(sync.evaluate_tests(1, "error: cannot find 'Foo' in scope", [FLAKY])[0], "fail")

    def test_unsettled_test_preferences_fail(self):
        output = harness_output(("NotchCompactTests", 339, FLAKY)) + "\n✗ test preferences did not settle"
        self.assertEqual(sync.evaluate_tests(1, output, [FLAKY])[0], "fail")

    def test_the_shipped_list_names_the_flaky_notch_check(self):
        self.assertIn(FLAKY, sync.load_flaky_patterns())


class Summary(unittest.TestCase):
    def setUp(self):
        self.path = Path(tempfile.mkdtemp()) / "summary.md"

    def test_a_sync_without_claude_says_so(self):
        sync.write_summary(self.path, "v3.4.5", [])
        self.assertEqual(self.path.read_text(), f"# 同步上游 v3.4.5\n\n{sync.NOTHING_TO_DO}\n")

    def test_a_rerun_for_the_same_tag_keeps_what_claude_did(self):
        sync.write_summary(self.path, "v3.4.5", ["解衝突「a」\n- x：y"])
        sync.write_summary(self.path, "v3.4.5", [])
        self.assertIn("解衝突「a」", self.path.read_text())

    def test_a_note_both_runs_made_appears_once(self):
        flaky = "已知不穩定的官方測試失敗，照常放行：\n- " + FLAKY
        sync.write_summary(self.path, "v3.4.5", ["解衝突「a」\n- x：y", flaky])
        sync.write_summary(self.path, "v3.4.5", [flaky])
        text = self.path.read_text()
        self.assertEqual(text.count(flaky), 1)
        self.assertIn("解衝突「a」", text)

    def test_a_new_tag_starts_over(self):
        sync.write_summary(self.path, "v3.4.5", ["解衝突「a」"])
        sync.write_summary(self.path, "v3.4.6", [])
        self.assertEqual(self.path.read_text(), f"# 同步上游 v3.4.6\n\n{sync.NOTHING_TO_DO}\n")


class Status(unittest.TestCase):
    def test_the_app_reads_back_what_the_script_wrote(self):
        path = Path(tempfile.mkdtemp()) / "status.json"
        sync.Status(path, "v3.4.5", "run-1").write("running", "正在跑測試", 0.12)
        record = sync.read_status(path)
        self.assertEqual((record["state"], record["title"], record["fraction"], record["pid"], record["runId"]),
                         ("running", "正在跑測試", 0.12, os.getpid(), "run-1"))


class RebaseBase(unittest.TestCase):
    """upstream main: c0 (v0.9.0) - c1 (v1.0.0) - c2 (v1.1.0); custom: v1.0.0 + f1."""

    def setUp(self):
        self.repo = tempfile.mkdtemp()
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
        self.env = env
        self.git("init", "-q", "-b", "main")
        self.commits = {}
        for name, tag in [("c0", "v0.9.0"), ("c1", "v1.0.0"), ("c2", "v1.1.0")]:
            self.commit(name)
            self.git("tag", tag)
            self.commits[name] = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/upstream/main", "main")
        self.git("checkout", "-q", "-b", "custom", "v1.0.0")
        self.commit("f1")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env, check=True,
                              text=True, stdout=subprocess.PIPE).stdout.strip()

    def commit(self, name):
        Path(self.repo, name).write_text(name)
        self.git("add", name)
        self.git("commit", "-q", "-m", name)

    def resolve(self, tag):
        return sync.resolve_rebase_base(self.repo, "custom", tag, "upstream/main")

    def test_a_newer_release_moves_only_the_fork_commits(self):
        self.assertEqual(self.resolve("v1.1.0"), ("rebase", self.commits["c1"], False))

    def test_the_current_base_only_verifies(self):
        self.assertEqual(self.resolve("v1.0.0")[0], "already-based")

    def test_an_older_release_is_still_followed(self):
        self.assertEqual(self.resolve("v0.9.0"), ("rebase", self.commits["c1"], True))


if __name__ == "__main__":
    unittest.main()
