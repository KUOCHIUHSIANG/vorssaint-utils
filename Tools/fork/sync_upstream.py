#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Jater
"""Moves Neptater's own commits onto an official Vorssaint release and reinstalls it.

    python3 Tools/fork/sync_upstream.py v3.4.5 [--from-app] [--run-id ID] [--skip-install]

Steps: fetch upstream tags -> back up `custom` (replacing the previous backup)
-> rebase the fork's own commits onto the tag, with rerere -> ./build.sh --test
-> ./build.sh -> selftest -> keep a copy of the installed app -> quit Neptater
-> ./build.sh --install -> relaunch it and check that it stays up -> remove build/.

Conflicts rerere cannot replay, and failing tests or builds, go to headless
Claude Code; what it did goes to .git/neptater-sync-summary.md, which the
relaunched app shows once. Any failure resets `custom` to where it started and
keeps (or restores) the installed app, so a sync either lands whole or not at all.

Progress for the app goes to .git/neptater-sync-status.json. With --from-app
(how Neptater's update button starts it) the log goes to .git/neptater-sync.log.
--run-id tags every progress record, so the app never mistakes the previous
sync's record for this one. --skip-install stops after the selftest, leaving
the installed app alone.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
UPSTREAM = "upstream"
BRANCH = "custom"
RELEASE_TAG = re.compile(r"^v\d+\.\d+\.\d+$")
RERERE = ["-c", "rerere.enabled=true", "-c", "rerere.autoUpdate=true"]
APP = Path("/Applications/Neptater.app")
EXECUTABLE = "Neptater"
BUNDLE_ID = "io.github.kuochiuhsiang.neptater"
FLAKY_TESTS_FILE = Path(__file__).resolve().parent / "known-flaky-tests.txt"
CLAUDE_TIMEOUT_SECONDS = 20 * 60
MAX_REPAIRS = 2
OUTPUT_TAIL_CHARS = 40_000
# Started from the app, PATH is launchd's minimal one; Claude Code lives elsewhere.
EXTRA_PATH = ["/opt/homebrew/bin", "/usr/local/bin",
              str(Path.home() / ".local/bin"), str(Path.home() / ".claude/local")]
# Every passing `./build.sh --test` prints these after the Swift suites.
SCRIPT_TEST_MARKERS = ["PREFERENCE CLEANUP TESTS OK", "UNINSTALL SPACES TESTS OK",
                       "DEVELOPER INSTALL ISOLATION TESTS OK"]
NOTHING_TO_DO = "不需要 Claude Code 介入。"

READ_ONLY_GIT_TOOLS = ["Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
                       "Bash(git status:*)", "Bash(git grep:*)"]
FILE_TOOLS = ["Read", "Edit", "Write", "Grep", "Glob"]
# Why so strict: the final message is shown verbatim after the update.
SUMMARY_INSTRUCTION = (
    "Your final message is shown to the user as-is: write only the summary, in Traditional "
    "Chinese, one short line per file you changed (`- <file>：<what you did>`), with no preamble "
    "or closing remarks.")


class SyncFailed(Exception):
    pass


def log(message):
    print(f"[sync-upstream] {message}", flush=True)


def git(*args, cwd=REPO):
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE).stdout.strip()


def succeeds(command, env=None, cwd=REPO):
    log("$ " + " ".join(command))
    return subprocess.run(command, cwd=cwd, env=env, stdout=sys.stdout, stderr=sys.stdout).returncode == 0


def run_captured(command, cwd=REPO):
    """Runs a long step, echoing its output to the log; returns (exit code, output)."""
    log("$ " + " ".join(command))
    process = subprocess.Popen(command, cwd=cwd, text=True, errors="replace",
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = []
    for line in process.stdout:
        sys.stdout.write(line)
        lines.append(line)
    sys.stdout.flush()
    return process.wait(), "".join(lines)


def search_path():
    parts = os.environ.get("PATH", "").split(os.pathsep)
    return os.pathsep.join(parts + [p for p in EXTRA_PATH if p not in parts])


# MARK: - Status for the app


class Status:
    """What the app shows while the sync runs, written atomically on every change."""

    def __init__(self, path, tag, run_id=None):
        self.path = path
        self.tag = tag
        self.run_id = run_id

    def write(self, state, title, fraction=None, message=None):
        record = {"pid": os.getpid(), "runId": self.run_id, "tag": self.tag, "state": state, "title": title,
                  "fraction": fraction, "message": message, "updatedAt": time.time()}
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(record, ensure_ascii=False))
        temporary.replace(self.path)

    def running(self, title, fraction):
        log(title)
        self.write("running", title, fraction)


def read_status(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except (OSError, TypeError):
        return False


# MARK: - Where the rebase starts


def resolve_rebase_base(cwd, branch, target_tag, upstream_main):
    """Returns (kind, base, rolls_back): only the fork's own commits may move to the tag.

    Why not `git describe`: the fork can sit past its newest tag, and rebasing
    from that tag would replay upstream commits the target already contains.
    A target cut from an older base (a re-cut release) is still followed: the
    single boundary between upstream history and the fork's commits marks them.
    """
    def run(*args):
        return git(*args, cwd=cwd)

    target = run("rev-parse", f"{target_tag}^{{commit}}")
    fork_point = run("merge-base", branch, upstream_main)
    contains = subprocess.run(["git", "merge-base", "--is-ancestor", fork_point, target],
                              cwd=cwd).returncode == 0
    merge_base = run("merge-base", branch, target)
    if contains and merge_base == target:
        return "already-based", target, False
    boundary = [line[1:] for line in
                run("rev-list", "--boundary", branch, "--not", upstream_main, "--tags=v[0-9]*").split("\n")
                if line.startswith("-")]
    if contains:
        return "rebase", boundary[0] if len(boundary) == 1 else merge_base, False
    if len(boundary) != 1:
        return "unknown-base", fork_point, False
    return "rebase", boundary[0], True


# MARK: - Claude Code


def run_claude(prompt, allowed_tools):
    """Returns (True, summary) or (False, reason)."""
    claude = shutil.which("claude", path=search_path())
    if not claude:
        return False, "找不到 claude 指令"
    log("Asking Claude Code")
    try:
        result = subprocess.run(
            [claude, "-p", "--output-format", "json",
             # Why: MCP servers only slow startup and leak status into the summary.
             "--strict-mcp-config", "--permission-mode", "acceptEdits",
             "--allowedTools", ",".join(allowed_tools)],
            cwd=REPO, input=prompt, text=True, stdout=subprocess.PIPE, stderr=sys.stdout,
            timeout=CLAUDE_TIMEOUT_SECONDS, env={**os.environ, "PATH": search_path()})
    except subprocess.TimeoutExpired:
        return False, f"Claude Code 超過 {CLAUDE_TIMEOUT_SECONDS // 60} 分鐘未完成"
    if result.returncode != 0:
        return False, f"Claude Code 執行失敗（exit {result.returncode}）"
    try:
        output = json.loads(result.stdout)
        text = str(output.get("result", "")).strip()
        is_error = output.get("is_error") is True
    except ValueError:
        text, is_error = result.stdout.strip(), False
    log(f"Claude Code:\n{text}")
    if is_error:
        return False, f"Claude Code 執行失敗（{text[:120]}）"
    return True, text


CONFLICT_MARKER = re.compile(r"^(<{7}|>{7}) ", re.MULTILINE)


def marker_count(text):
    return len(CONFLICT_MARKER.findall(text))


def index_text(stage, file):
    result = subprocess.run(["git", "show", f":{stage}:{file}"], cwd=REPO, text=True,
                            errors="replace", stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return result.stdout if result.returncode == 0 else ""


def still_conflicted(file):
    """Markers beyond what the index already holds (say, a test fixture) are leftovers."""
    path = REPO / file
    if not path.is_file():
        return False
    expected = max(marker_count(index_text(stage, file)) for stage in (0, 2, 3))
    return marker_count(path.read_text(errors="replace")) > expected


def resolve_conflicts_with_claude(files, tag):
    commit = git("rev-parse", "--short", "REBASE_HEAD")
    subject = git("log", "-1", "--format=%s", "REBASE_HEAD")
    prompt = "\n".join([
        "A `git rebase` in this repository is paused on conflicts. Resolve them.",
        f"Neptater, a personal fork of Vorssaint, is being re-stacked onto upstream release {tag}.",
        f'The commit being replayed is {commit} "{subject}".',
        "In each conflict the HEAD side is the new upstream code plus fork commits already "
        "replayed; the other side is that fork commit.",
        "",
        "Conflicted files:",
        *[f"- {file}" for file in files],
        "",
        f"Keep upstream's changes and still apply what the fork commit intended. Use `git show {commit}` "
        "to see that intent. Follow CONTRIBUTING.md.",
        "If upstream renamed or moved something this commit uses, also update the other files of this "
        "commit that reference it.",
        "Only edit files. Do not stage, commit, or run git commands that change state; the sync script "
        "verifies and continues the rebase itself. If the right resolution is deleting a file, use "
        "`git rm <file>`.",
        "Do not build or run tests: the sync script does that after the rebase and asks for fixes if needed.",
        "If you cannot resolve a conflict with confidence, leave its markers in place so the update "
        "stops for a manual resolution.",
        SUMMARY_INSTRUCTION,
    ])
    ok, text = run_claude(prompt, FILE_TOOLS + READ_ONLY_GIT_TOOLS + ["Bash(git rm:*)"])
    if not ok:
        return False, text
    changed = git("diff", "--name-only").split("\n") + git("ls-files", "--others", "--exclude-standard").split("\n")
    leftover = [file for file in dict.fromkeys(files + [f for f in changed if f]) if still_conflicted(file)]
    if leftover:
        return False, f"Claude Code 未解完：{', '.join(leftover)}"
    # Why the whole tree: a resolution can need edits outside the conflicted files.
    git("add", "-A")
    return True, text


VERIFY_TOOLS = ["Bash(./build.sh --test)", "Bash(./build.sh --test-suite:*)",
                "Bash(./build.sh --list-tests)", "Bash(./build.sh)", f"Bash(./build/{EXECUTABLE} --selftest)"]


def repair_with_claude(tag, base, command, output):
    prompt = "\n".join([
        f"Neptater, a personal fork of Vorssaint, was just rebased onto upstream release {tag}, "
        f"and `{' '.join(command)}` now fails:",
        "",
        "```",
        output[-OUTPUT_TAIL_CHARS:],
        "```",
        "",
        f"The fork's own commits are `git log {tag}..HEAD`; use `git show` on them to see what each "
        f"intended, and `git diff {base} {tag} -- <path>` for what upstream changed in a file.",
        "Fix the failure by adapting the fork's code to the new upstream code; do not revert upstream "
        "changes. Follow CONTRIBUTING.md.",
        "If the failure is in upstream code or tests the fork never touched, do not change them: leave "
        "it and say so.",
        "To check your fix, run exactly one of `./build.sh --test`, `./build.sh --test-suite=<suite>`, "
        f"`./build.sh --list-tests`, `./build.sh` or `./build/{EXECUTABLE} --selftest`, without pipes. "
        "Never run `./build.sh --install` or `--dev`.",
        "Only edit files. Do not stage or commit; the sync script commits your changes.",
        "If you cannot fix it with confidence, leave it and say why.",
        SUMMARY_INSTRUCTION,
    ])
    return run_claude(prompt, FILE_TOOLS + READ_ONLY_GIT_TOOLS + VERIFY_TOOLS)


def claude_said(text):
    return f"\nClaude Code 的說明：\n{text[:800]}" if text else ""


# MARK: - Tests


def load_flaky_patterns(path=FLAKY_TESTS_FILE):
    try:
        lines = path.read_text().split("\n")
    except OSError:
        return []
    return [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]


FAILURE_LINE = re.compile(r"^\s+- (?P<location>\S+:\d+): (?P<message>.*)$")


def parse_test_failures(output):
    """The `- file:line: message` lines under the Swift harness's TESTS FAILED header."""
    failures = []
    collecting = False
    for line in output.split("\n"):
        if line.startswith("TESTS FAILED ("):
            collecting = True
            continue
        if collecting:
            match = FAILURE_LINE.match(line)
            if not match:
                collecting = False
                continue
            failures.append((match["location"], match["message"]))
    return failures


def evaluate_tests(exit_code, output, flaky_patterns):
    """Returns ("pass" | "flaky" | "fail", failures).

    "flaky" means every failure is a known-unstable upstream check and every
    other part of the run passed, so the update goes on and says so.
    """
    if exit_code == 0:
        return "pass", []
    failures = parse_test_failures(output)
    known = failures and all(any(pattern in message for pattern in flaky_patterns)
                             for _, message in failures)
    others_passed = all(marker in output for marker in SCRIPT_TEST_MARKERS) \
        and "✗ test preferences" not in output
    return ("flaky" if known and others_passed else "fail"), failures


# MARK: - Summary


def write_summary(path, tag, notes):
    """Keeps the summary of how `tag` was reached; a re-run for the same tag adds to it.

    Why keep the earlier run's notes: after a rolled-back attempt, rerere replays
    the conflict resolutions Claude made then, and the re-run has nothing new to say
    about them. Each paragraph appears once, so a note both runs made is not repeated.
    """
    header = f"# 同步上游 {tag}\n\n"
    existing = path.read_text() if path.exists() else ""
    previous = existing[len(header):].strip() if existing.startswith(header) else ""
    if previous and not notes:
        return
    paragraphs = [paragraph.strip() for block in [previous, *notes] for paragraph in block.split("\n\n")]
    sections = list(dict.fromkeys(p for p in paragraphs if p and p != NOTHING_TO_DO))
    path.write_text(header + ("\n\n".join(sections) if sections else NOTHING_TO_DO) + "\n")


# MARK: - The sync


class Sync:
    def __init__(self, tag, from_app, skip_install, run_id=None):
        self.tag = tag
        self.from_app = from_app
        self.skip_install = skip_install
        self.git_dir = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir"))
        self.status = Status(self.git_dir / "neptater-sync-status.json", tag, run_id)
        self.summary_path = self.git_dir / "neptater-sync-summary.md"
        self.previous_app = self.git_dir / "neptater-previous.app"
        self.notes = []
        self.rollback_to = None
        self.app_was_quit = False

    def preflight(self):
        if not RELEASE_TAG.match(self.tag):
            raise SyncFailed(f"{self.tag} 不是正式版 tag（vX.Y.Z）")
        current = read_status(self.status.path)
        if current and current.get("state") == "running" and current.get("pid") != os.getpid() \
                and pid_alive(current.get("pid")):
            raise SyncFailed("已經有另一個同步正在執行")
        if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
            raise SyncFailed(f"{REPO} 目前不在 {BRANCH} 分支，請先切回 {BRANCH}")
        dirty = [line[3:] for line in git("status", "--porcelain").split("\n") if line]
        if dirty:
            more = f" 等 {len(dirty)} 項" if len(dirty) > 3 else ""
            raise SyncFailed(f"{BRANCH} 有未提交的檔案，先 commit 或 stash：{'、'.join(dirty[:3])}{more}")

    def fetch(self):
        self.status.running(f"正在抓取官方 {self.tag}", 0.02)
        # Why an explicit refspec: upstream has thousands of branches that would bloat .git.
        if not succeeds(["git", "fetch", UPSTREAM, "--tags", "--prune",
                         f"+refs/heads/main:refs/remotes/{UPSTREAM}/main"]):
            raise SyncFailed(f"無法從 {UPSTREAM} 抓取 tag")
        if subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"refs/tags/{self.tag}"],
                          cwd=REPO, stdout=subprocess.DEVNULL).returncode != 0:
            raise SyncFailed(f"{UPSTREAM} 上沒有 {self.tag}")

    def rebase(self, base):
        own = git("log", "--oneline", f"{base}..HEAD")
        label = git("describe", "--tags", "--always", base)
        log(f"Moving these commits from {label} to {self.tag}:\n{own}")
        backup = f"backup/{BRANCH}-before-{self.tag}"
        git("branch", "-f", backup, "HEAD")
        # Why only one: a new sync means the previous backup's version proved stable.
        for branch in git("for-each-ref", "--format=%(refname:short)",
                          f"refs/heads/backup/{BRANCH}-before-*").split("\n"):
            if branch and branch != backup:
                git("branch", "-D", branch)
        self.status.running(f"正在把自訂 commit 移到 {self.tag}", 0.06)

        rebased = succeeds(["git", *RERERE, "rebase", "--onto", self.tag, base, BRANCH])
        stops_left = len(own.split("\n"))
        failed_continue_at = None
        reason = None
        while not rebased and stops_left > 0 and self.rebase_in_progress():
            stops_left -= 1
            stop = git("rev-parse", "REBASE_HEAD")
            files = self.conflicted_files()
            if not files and stop == failed_continue_at:
                reason = "沒有衝突檔，git rebase --continue 仍然失敗"
                break
            if files:
                subject = git("log", "-1", "--format=%s", "REBASE_HEAD")
                self.status.running(f"Claude Code 正在解衝突：{subject}", 0.08)
                ok, text = resolve_conflicts_with_claude(files, self.tag)
                if not ok:
                    reason = text
                    break
                self.notes.append(f"解衝突「{subject}」\n{text}")
            rebased = succeeds(["git", *RERERE, "rebase", "--continue"],
                               env={**os.environ, "GIT_EDITOR": "true"})
            failed_continue_at = None if rebased else stop
        if rebased:
            return
        files = self.conflicted_files()
        subject = git("log", "-1", "--format=%s", "REBASE_HEAD") if self.rebase_in_progress() else ""
        if self.rebase_in_progress():
            succeeds(["git", "rebase", "--abort"])
        detail = f"「{subject}」，衝突檔案：{'、'.join(files)}。" if files else ""
        raise SyncFailed(f"Rebase 衝突沒有自動解決{detail}{reason or ''}".rstrip("。") + "。")

    def rebase_in_progress(self):
        return (self.git_dir / "rebase-merge").exists() or (self.git_dir / "rebase-apply").exists()

    def conflicted_files(self):
        output = git("diff", "--name-only", "--diff-filter=U")
        return output.split("\n") if output else []

    def verify(self, base):
        steps = [
            (["./build.sh", "--test"], "正在跑測試", 0.12),
            (["./build.sh"], "正在建置 Neptater", 0.55),
            ([f"./build/{EXECUTABLE}", "--selftest"], "正在執行 selftest", 0.85),
        ]
        flaky_patterns = load_flaky_patterns()
        tolerated = set()
        repairs = 0
        last_explanation = ""
        while True:
            failure = None
            for command, title, fraction in steps:
                self.status.running(title, fraction)
                code, output = run_captured(command)
                if command[1:] == ["--test"]:
                    verdict, failures = evaluate_tests(code, output, flaky_patterns)
                    if verdict == "flaky":
                        tolerated.update(message for _, message in failures)
                        continue
                    if verdict == "pass":
                        continue
                elif code == 0:
                    continue
                failure = (command, output)
                break
            if failure is None:
                break
            command, output = failure
            label = " ".join(command)
            if repairs >= MAX_REPAIRS:
                raise SyncFailed(f"{label} 失敗，交給 Claude Code 修了 {repairs} 次仍然沒過。"
                                 + claude_said(last_explanation))
            repairs += 1
            self.status.running(f"Claude Code 正在修正 {label} 的錯誤", fraction)
            before = self.worktree_fingerprint()
            ok, text = repair_with_claude(self.tag, base, command, output)
            if not ok:
                raise SyncFailed(f"{label} 失敗，交給 Claude Code 修正也失敗：{text}")
            # Why stop: a repair that changes nothing means Claude found nothing the fork should fix,
            # say upstream's own code is broken, and another round would only repeat that.
            if self.worktree_fingerprint() == before:
                raise SyncFailed(f"{label} 失敗，Claude Code 判斷不是 fork 該修的問題，沒有改任何檔案。"
                                 + claude_said(text))
            last_explanation = text
            self.notes.append(f"修正 {label} 的錯誤\n{text}")
        if tolerated:
            self.notes.append("已知不穩定的官方測試失敗，照常放行：\n"
                              + "\n".join(f"- {message}" for message in sorted(tolerated)))
        if git("status", "--porcelain"):
            git("add", "-A")
            repair_notes = [note for note in self.notes if note.startswith("修正 ")]
            git("commit", "--no-verify", "-q", "-m", f"fix: 同步上游 {self.tag} 後修正建置錯誤",
                *(["-m", "\n\n".join(repair_notes)] if repair_notes else []))

    def worktree_fingerprint(self):
        """Changes since HEAD, including the content of new files."""
        digest = hashlib.sha256(git("status", "--porcelain").encode())
        digest.update(git("diff", "HEAD").encode())
        for file in git("ls-files", "--others", "--exclude-standard").split("\n"):
            if file:
                digest.update(git("hash-object", "--", file).encode())
        return digest.hexdigest()

    def running_app_pids(self):
        # Why -a: pgrep skips its own ancestors, and started from the app, Neptater is one.
        result = subprocess.run(["pgrep", "-a", "-x", EXECUTABLE], text=True, stdout=subprocess.PIPE)
        return [int(pid) for pid in result.stdout.split()]

    def quit_app(self):
        pids = self.running_app_pids()
        if not pids:
            return
        self.app_was_quit = True
        # Started from the app, the app quits itself on seeing "installing": asking it over
        # Apple Events would need an Automation grant from Neptater to itself. Builds from
        # before that behaviour, and runs from a terminal, are asked after a grace period.
        ask_at = time.time() + (15 if self.from_app else 0)
        asked = False
        deadline = time.time() + 75
        while any(pid_alive(pid) for pid in pids):
            if not asked and time.time() >= ask_at:
                asked = True
                # Why not wait on osascript: a dialog in the app would block it; the exit is what counts.
                subprocess.Popen(["osascript", "-e", f'tell application id "{BUNDLE_ID}" to quit'],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if time.time() > deadline:
                raise SyncFailed("Neptater 沒有結束（可能有對話框等你回應），沒有安裝新版")
            time.sleep(0.5)

    def restore_previous_app(self):
        if not self.previous_app.exists():
            return "找不到安裝前的備份，/Applications 裡的 Neptater 可能已經不完整"
        shutil.rmtree(APP, ignore_errors=True)
        if not succeeds(["ditto", str(self.previous_app), str(APP)]):
            return f"還原舊版失敗，請手動把 {self.previous_app} 複製回 {APP}"
        shutil.rmtree(self.previous_app, ignore_errors=True)
        return "已還原舊版 Neptater。"

    def stays_up(self):
        """Gives the relaunched app time to crash on start before calling the install good."""
        for _ in range(30):
            if self.running_app_pids():
                break
            time.sleep(0.5)
        else:
            return False
        time.sleep(10)
        return bool(self.running_app_pids())

    def install(self):
        shutil.rmtree(self.previous_app, ignore_errors=True)
        if APP.exists() and not succeeds(["ditto", str(APP), str(self.previous_app)]):
            raise SyncFailed("無法備份目前安裝的 Neptater，沒有安裝新版")
        self.status.write("installing", "正在安裝並重新啟動 Neptater", 0.95)
        log("Quitting Neptater and installing")
        self.quit_app()
        code, _ = run_captured(["./build.sh", "--install"])
        if code != 0:
            raise SyncFailed(f"安裝失敗（exit {code}）。{self.restore_previous_app()}")
        # Why a new state before opening it: the new build follows this record too, and
        # must not take "installing" as its own cue to quit.
        self.status.write("launching", "正在確認新版 Neptater 正常執行", 0.98)
        succeeds(["open", str(APP)])
        if not self.stays_up():
            raise SyncFailed(f"新版 Neptater 啟動後沒有持續執行。{self.restore_previous_app()}")
        shutil.rmtree(self.previous_app, ignore_errors=True)

    def roll_back(self):
        commit = self.rollback_to
        self.rollback_to = None
        try:
            if self.rebase_in_progress():
                succeeds(["git", "rebase", "--abort"])
            if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
                git("checkout", "-q", BRANCH)
            # Why add first: reset --hard then also removes files Claude created.
            git("add", "-A")
            git("reset", "--hard", "-q", commit)
            return f"{BRANCH} 已還原到同步前的狀態。"
        except subprocess.CalledProcessError:
            return f"{BRANCH} 還原失敗，請手動 git reset --hard {commit}。"

    def run(self):
        self.preflight()
        self.status.running("準備同步", 0.01)
        self.fetch()
        kind, base, rolls_back = resolve_rebase_base(REPO, "HEAD", self.tag, f"{UPSTREAM}/main")
        if kind == "unknown-base":
            raise SyncFailed(f"{self.tag} 比 {BRANCH} 的起點還舊，找不到單一的 upstream 起點可以搬移自訂 commit")
        if rolls_back:
            log(f"{self.tag} was cut from an older base; upstream commits it leaves out are dropped too.")
        self.rollback_to = git("rev-parse", "HEAD")
        if kind == "already-based":
            log(f"Already based on {self.tag}; verifying only.")
        else:
            self.rebase(base)
        self.verify(base)
        write_summary(self.summary_path, self.tag, self.notes)
        if not self.skip_install:
            self.install()
            # Why: build outputs are 700 MB and the next sync rebuilds anyway.
            shutil.rmtree(REPO / "build", ignore_errors=True)
        self.rollback_to = None
        self.status.write("done", f"已更新到 {self.tag}", 1.0)
        log(f"{BRANCH} is now based on {self.tag}.")

    def fail(self, message):
        if self.rollback_to:
            ending = "" if message.rstrip().endswith(("。", "\n")) else "。"
            message = f"{message.rstrip()}{ending}\n{self.roll_back()}"
        if self.app_was_quit and not self.running_app_pids():
            succeeds(["open", str(APP)])
        self.status.write("failed", "更新失敗", None, message)
        log(f"FAILED: {message}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("tag")
    parser.add_argument("--from-app", action="store_true")
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--run-id")
    args = parser.parse_args(argv)

    if args.from_app:
        log_file = open(Path(git("rev-parse", "--path-format=absolute", "--git-common-dir"))
                        / "neptater-sync.log", "a", buffering=1)
        sys.stdout = sys.stderr = log_file
    log(f"{time.strftime('%Y-%m-%d %H:%M:%S')} syncing {BRANCH} to {args.tag}")
    os.environ["PATH"] = search_path()
    sync = Sync(args.tag, args.from_app, args.skip_install, args.run_id)
    try:
        sync.run()
    except SyncFailed as error:
        sync.fail(str(error))
        return 1
    except Exception as error:  # noqa: BLE001 - any crash must still roll back and report
        sync.fail(f"同步程式發生錯誤：{error}")
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main())
