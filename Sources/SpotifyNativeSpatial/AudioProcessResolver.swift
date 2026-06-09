import AppKit
import AudioToolbox
import Foundation

struct AppAudioProcess: Hashable {
    let pid: pid_t
    let objectID: AudioObjectID
    let name: String
    let bundleID: String?
    let path: String?
    let appBundleID: String?
    let appPath: String?
    let appName: String
    let audioActive: Bool
}

struct AudioAppTarget: Hashable {
    let key: String
    let displayName: String
    let bundleID: String?
    let appPath: String?
    let processes: [AppAudioProcess]

    var audioActive: Bool {
        processes.contains(where: \.audioActive)
    }

    var processCount: Int {
        processes.count
    }
}

extension AudioAppTarget: Identifiable {
    var id: String { key }
}

enum AudioProcessResolver {
    static let spotifyBundleID = "com.spotify.client"

    static func resolveSpotify() throws -> [AppAudioProcess] {
        try resolveProcesses().filter { process in
            process.appBundleID == spotifyBundleID ||
                process.bundleID == spotifyBundleID ||
                process.appPath?.hasSuffix("/Spotify.app") == true ||
                process.path?.contains("/Spotify.app/") == true
        }
    }

    static func resolveApps() throws -> [AudioAppTarget] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let processes = try resolveProcesses()
            .filter { process in
                process.pid != ProcessInfo.processInfo.processIdentifier &&
                    process.appPath != nil &&
                    process.appBundleID != ownBundleID
            }

        let grouped = Dictionary(grouping: processes) { process in
            process.appBundleID ?? process.appPath ?? process.bundleID ?? "pid:\(process.pid)"
        }

        return grouped.map { key, processes in
            let sortedProcesses = processes.sorted { lhs, rhs in
                if lhs.audioActive != rhs.audioActive {
                    return lhs.audioActive && !rhs.audioActive
                }

                return lhs.pid < rhs.pid
            }

            let representative = sortedProcesses[0]
            return AudioAppTarget(
                key: key,
                displayName: representative.appName,
                bundleID: representative.appBundleID ?? representative.bundleID,
                appPath: representative.appPath,
                processes: sortedProcesses
            )
        }
        .sorted { lhs, rhs in
            if lhs.audioActive != rhs.audioActive {
                return lhs.audioActive && !rhs.audioActive
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func resolveProcesses() throws -> [AppAudioProcess] {
        var matches: [AppAudioProcess] = []

        for objectID in try AudioObjectID.readProcessList() {
            guard let process = AppAudioProcess(objectID: objectID) else {
                continue
            }

            matches.append(process)
        }

        let existingPIDs = Set(matches.map(\.pid))
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0, !existingPIDs.contains(pid) else {
                continue
            }

            guard let objectID = try? AudioObjectID.translatePIDToProcessObjectID(pid: pid),
                  let process = AppAudioProcess(objectID: objectID) else {
                continue
            }

            matches.append(process)
        }

        return Array(Set(matches)).sorted { lhs, rhs in
            if lhs.audioActive != rhs.audioActive {
                return lhs.audioActive && !rhs.audioActive
            }

            return lhs.pid < rhs.pid
        }
    }
}

private extension AppAudioProcess {
    init?(objectID: AudioObjectID) {
        guard let pid = try? objectID.readProcessPID(), pid > 0 else {
            return nil
        }

        let info = processInfo(for: pid)
        let bundleID = objectID.readProcessBundleID()
        let appBundle = appBundleInfo(path: info?.path, processBundleID: bundleID)

        self.init(
            pid: pid,
            objectID: objectID,
            name: info?.name ?? bundleID?.components(separatedBy: ".").last ?? "pid-\(pid)",
            bundleID: bundleID,
            path: info?.path,
            appBundleID: appBundle.bundleID,
            appPath: appBundle.path,
            appName: appBundle.name ?? info?.name ?? bundleID?.components(separatedBy: ".").last ?? "pid-\(pid)",
            audioActive: objectID.readProcessIsRunning()
        )
    }
}

private func processInfo(for pid: pid_t) -> (name: String, path: String)? {
    let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
    let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))

    defer {
        nameBuffer.deallocate()
        pathBuffer.deallocate()
    }

    let nameLength = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
    let pathLength = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))

    guard nameLength > 0, pathLength > 0 else {
        return nil
    }

    return (String(cString: nameBuffer), String(cString: pathBuffer))
}

private func appBundleInfo(path: String?, processBundleID: String?) -> (path: String?, bundleID: String?, name: String?) {
    guard let path else {
        return (nil, processBundleID, nil)
    }

    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
        return (nil, processBundleID, nil)
    }

    let appPath = components[0...appIndex].joined(separator: "/")
    let url = URL(fileURLWithPath: appPath)
    let bundle = Bundle(url: url)
    let bundleID = bundle?.bundleIdentifier ?? processBundleID
    let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
    let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

    return (appPath, bundleID, name)
}
