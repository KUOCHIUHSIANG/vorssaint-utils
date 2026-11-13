// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import AppKit
import CryptoKit

/// Neptater follows official Vorssaint releases by rebuilding itself: its
/// checkout re-stacks the fork's commits onto the new release tag, verifies,
/// reinstalls and relaunches (Tools/fork/sync_upstream.py). This side finds the
/// release, starts that script, mirrors its progress into UpdateService's
/// published state, and reports the outcome once.
final class NeptaterForkUpdate {
    static let shared = NeptaterForkUpdate()

    /// The script's progress record, `.git/neptater-sync-status.json`.
    struct SyncStatus: Decodable, Equatable {
        let pid: Int32
        let runId: String?
        let tag: String
        let state: String
        let title: String?
        let fraction: Double?
        let message: String?
        let updatedAt: Double
    }

    private static let officialReleaseURL =
        URL(string: "https://api.github.com/repos/vorssaint/vorssaint-utils/releases/latest")!
    private static let seenSummaryKey = "neptaterSeenSyncSummary"
    private static let seenFailureKey = "neptaterSeenSyncFailure"
    /// Replaces "Couldn't check" in front of a failed rebuild's reason.
    private static let failedTitle = "更新失敗："

    /// build.sh stamps where the checkout lives and which release it was built from.
    private let repoRoot = Bundle.main.object(forInfoDictionaryKey: "NeptaterRepoRoot") as? String
    private let baseTag = Bundle.main.object(forInfoDictionaryKey: "NeptaterBaseTag") as? String
    private var latestTag: String?
    private var notifiedTag: String?
    private var pollTimer: Timer?
    private var isChecking = false
    /// The run this app started, and when: until the script writes a record
    /// for it, the file still holds the previous sync's outcome.
    private var awaitedRun: (id: String, since: Date)?
    private var isQuittingForInstall = false
    /// Tells the build being replaced from the one the script just started.
    private let launchedAt = Date()

    private init() {}

    private var gitDirectory: URL? {
        repoRoot.map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(".git") }
    }
    private var statusURL: URL? { gitDirectory?.appendingPathComponent("neptater-sync-status.json") }
    private var summaryURL: URL? { gitDirectory?.appendingPathComponent("neptater-sync-summary.md") }
    private var scriptPath: String? { repoRoot.map { "\($0)/Tools/fork/sync_upstream.py" } }

    // MARK: - Launch

    /// Resumes following a sync that is still running, and reports the last
    /// one if this launch has not seen how it ended.
    func launchDidFinish() {
        if let status = readStatus(), ["running", "installing", "launching"].contains(status.state),
           Self.isAlive(status.pid) {
            follow()
            return
        }
        if let status = readStatus(), status.state == "failed",
           Date().timeIntervalSince1970 - status.updatedAt < 24 * 60 * 60,
           markSeen(key: Self.seenFailureKey, content: "\(status.tag)\(status.updatedAt)") {
            present(title: "Neptater 沒有更新到 \(status.tag)",
                    text: status.message ?? "同步失敗，詳見 .git/neptater-sync.log。")
        }
        presentSummaryIfNeeded()
    }

    /// The summary the script left for the release this build is based on.
    private func presentSummaryIfNeeded() {
        guard let baseTag, let summaryURL,
              let text = try? String(contentsOf: summaryURL, encoding: .utf8) else { return }
        let header = "# 同步上游 \(baseTag)\n"
        guard text.hasPrefix(header),
              markSeen(key: Self.seenSummaryKey, content: text) else { return }
        let body = text.dropFirst(header.count).trimmingCharacters(in: .whitespacesAndNewlines)
        present(title: "Neptater 已更新到 \(baseTag)", text: body)
    }

    // MARK: - Check

    /// Compares the newest official release with the one this build is based on.
    /// Why "differs" rather than "newer": Neptater follows what upstream ships,
    /// even a release re-cut from an older base.
    func check(manual: Bool) {
        let updates = UpdateService.shared
        if pollTimer != nil || isChecking { return }
        guard let baseTag, repoRoot != nil else {
            updates.applyForkState(.failed("這個 Neptater 不是從 repo 建置的，無法自動更新"), checkedNow: true)
            return
        }
        isChecking = true
        updates.applyForkState(.checking)
        var request = URLRequest(url: Self.officialReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Neptater/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                guard let data, let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    updates.applyForkState(.failed(error?.localizedDescription ?? "無法取得官方正式版資訊"),
                                           checkedNow: true)
                    return
                }
                guard release.tagName != baseTag else {
                    self.latestTag = nil
                    updates.applyForkState(.upToDate, checkedNow: true)
                    return
                }
                self.latestTag = release.tagName
                let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                updates.applyForkState(.available(version: version),
                                       notes: ReleaseNotes.inAppUpdateNotes(from: release.body),
                                       checkedNow: true)
                if !manual, release.tagName != self.notifiedTag {
                    self.notifiedTag = release.tagName
                    Notifier.post(title: "Neptater 可以更新",
                                  body: "官方發布了 \(release.tagName)，按下更新會重新 rebase 並建置 Neptater。")
                }
            }
        }.resume()
    }

    // MARK: - Sync

    /// Starts the script in its own session (it quits and relaunches this app),
    /// then follows its progress record.
    func syncAndInstall() {
        // The outcome arrives as a notification, often after the app restarted.
        Notifier.requestPermission()
        let updates = UpdateService.shared
        guard let tag = latestTag, let scriptPath, let repoRoot,
              FileManager.default.fileExists(atPath: scriptPath) else {
            updates.applyForkState(.failed("找不到同步腳本，請確認 Neptater 的 repo 還在原處"),
                                   progressTitle: Self.failedTitle)
            return
        }
        let runID = UUID().uuidString
        do {
            try DetachedProcess.spawn("/usr/bin/python3",
                                      ["-I", scriptPath, tag, "--from-app", "--run-id", runID])
        } catch {
            updates.applyForkState(.failed("無法啟動同步腳本：\(error.localizedDescription)"),
                                   progressTitle: Self.failedTitle)
            return
        }
        awaitedRun = (runID, Date())
        updates.applyForkState(.downloading(progress: 0.01), progressTitle: "準備同步 \(tag)")
        Notifier.post(title: "Neptater 開始更新到 \(tag)",
                      body: "會在背景 rebase、測試並建置，完成後自動重新啟動。過程記錄在 \(repoRoot)/.git/neptater-sync.log。")
        // The script writes its first record a moment after it starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.follow() }
    }

    private func follow() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    private func poll() {
        let updates = UpdateService.shared
        let status = readStatus()
        if let awaited = awaitedRun {
            guard let status, status.runId == awaited.id else {
                if Date().timeIntervalSince(awaited.since) > 30 {
                    awaitedRun = nil
                    stopFollowing()
                    updates.applyForkState(.failed("同步腳本沒有啟動，詳見 .git/neptater-sync.log"),
                                           progressTitle: Self.failedTitle, checkedNow: true)
                }
                return
            }
            awaitedRun = nil
        }
        guard let status else { return }
        switch status.state {
        case "running" where Self.isAlive(status.pid):
            updates.applyForkState(.downloading(progress: status.fraction), progressTitle: status.title)
        case "installing" where Self.isAlive(status.pid):
            updates.applyForkState(.installing, progressTitle: status.title)
            // The script waits for this exit before it replaces the bundle, and
            // relaunches the new build. Quitting ourselves needs no Apple Events
            // permission, which a script asking this app to quit would. Only a
            // build running since before the record quits; a later one is the
            // replacement, though the script writes "launching" before it opens it.
            if !isQuittingForInstall, status.updatedAt > launchedAt.timeIntervalSince1970 {
                isQuittingForInstall = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        case "launching" where Self.isAlive(status.pid):
            // The script is checking that this new build stays up.
            updates.applyForkState(.installing, progressTitle: status.title)
        case "failed":
            stopFollowing()
            let message = status.message ?? "同步失敗"
            _ = markSeen(key: Self.seenFailureKey, content: "\(status.tag)\(status.updatedAt)")
            updates.applyForkState(.failed(message), progressTitle: Self.failedTitle, checkedNow: true)
            Notifier.post(title: "Neptater 沒有更新到 \(status.tag)", body: message)
        case "done":
            stopFollowing()
            updates.applyForkState(.upToDate, checkedNow: true)
            presentSummaryIfNeeded()
        default:
            stopFollowing()
            updates.applyForkState(.failed("同步程式意外結束，詳見 .git/neptater-sync.log"),
                                   progressTitle: Self.failedTitle, checkedNow: true)
        }
    }

    private func stopFollowing() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Helpers

    private func readStatus() -> SyncStatus? {
        guard let statusURL, let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(SyncStatus.self, from: data)
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// True the first time `content` is seen under `key`.
    private func markSeen(key: String, content: String) -> Bool {
        let digest = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        guard UserDefaults.standard.string(forKey: key) != digest else { return false }
        UserDefaults.standard.set(digest, forKey: key)
        return true
    }

    /// A scrolling, selectable report, since Claude's summaries can run long.
    private func present(title: String, text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let alert = NSAlert()
            alert.messageText = title
            let scroll = NSTextView.scrollableTextView()
            scroll.frame = NSRect(x: 0, y: 0, width: 460, height: 220)
            scroll.hasVerticalScroller = true
            if let textView = scroll.documentView as? NSTextView {
                textView.string = text
                textView.isEditable = false
                textView.font = .systemFont(ofSize: 12)
                textView.textContainerInset = NSSize(width: 4, height: 6)
            }
            alert.accessoryView = scroll
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
        }
    }
}
