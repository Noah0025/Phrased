import Foundation

struct ScannedService: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let baseURL: String
    let model: String
}

struct InstalledPackage: Sendable {
    let name: String
    let shellCommand: [String]
}

struct InstallCheck: Sendable {
    let package: InstalledPackage?
    let check: @Sendable () async -> Bool

    static func package(_ package: InstalledPackage) -> Self {
        Self(package: package) {
            await LocalServiceScanner.shellCheck(package.shellCommand)
        }
    }

    static func custom(_ check: @escaping @Sendable () async -> Bool) -> Self {
        Self(package: nil, check: check)
    }
}

struct InstalledServiceCheck<ProbeResult: Sendable>: Sendable {
    let name: String
    let port: Int
    let checks: [InstallCheck]
    let mapRunningServices: @Sendable (_ baseURL: String, _ probeResult: ProbeResult) -> [ScannedService]
}

struct LocalServiceProbe<ProbeResult: Sendable>: Sendable {
    let port: Int
    let probe: @Sendable (_ baseURL: String) async -> ProbeResult?
}

actor LocalServiceScanner {
    static func scan<ProbeResult: Sendable>(
        portProbes: [LocalServiceProbe<ProbeResult>],
        installedServiceChecks: [InstalledServiceCheck<ProbeResult>],
        mapUnknownRunning: @escaping @Sendable (_ baseURL: String, _ port: Int, _ probeResult: ProbeResult) -> [ScannedService]
    ) async -> (services: [ScannedService], notRunning: [String]) {
        var installedServices: [InstalledServiceCheck<ProbeResult>] = []

        for service in installedServiceChecks {
            var installed = false
            for check in service.checks {
                if await check.check() {
                    installed = true
                    break
                }
            }

            if installed {
                installedServices.append(service)
            }
        }

        var probeResults: [Int: ProbeResult] = [:]
        await withTaskGroup(of: (Int, ProbeResult?).self) { group in
            for portProbe in portProbes {
                group.addTask {
                    let baseURL = "http://localhost:\(portProbe.port)"
                    return (portProbe.port, await portProbe.probe(baseURL))
                }
            }

            for await (port, result) in group {
                if let result {
                    probeResults[port] = result
                }
            }
        }

        var services: [ScannedService] = []
        var notRunning: [String] = []
        var handledPorts: Set<Int> = []

        for installedService in installedServices {
            let baseURL = "http://localhost:\(installedService.port)"
            if let result = probeResults[installedService.port] {
                services.append(contentsOf: installedService.mapRunningServices(baseURL, result))
                handledPorts.insert(installedService.port)
            } else {
                notRunning.append(installedService.name)
            }
        }

        for portProbe in portProbes where !handledPorts.contains(portProbe.port) {
            guard let result = probeResults[portProbe.port] else { continue }
            let baseURL = "http://localhost:\(portProbe.port)"
            services.append(contentsOf: mapUnknownRunning(baseURL, portProbe.port, result))
        }

        return (services, notRunning)
    }

    static func probeOpenAIModelList(at baseURL: String) async -> [String]? {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 1.5)
        request.httpMethod = "GET"

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            return nil
        }

        return list.compactMap { $0["id"] as? String }.sorted()
    }

    static func probeOpenAICompatibleModelEndpoint(at baseURL: String) async -> Bool? {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 1.5)
        request.httpMethod = "GET"

        let ok = (try? await URLSession.shared.data(for: request))
            .map { _, response in
                (response as? HTTPURLResponse)?.statusCode == 200
            } ?? false

        return ok ? true : nil
    }

    static func shellCheck(_ args: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    static func appInstalled(_ appName: String) -> Bool {
        let fileManager = FileManager.default
        let paths = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ]
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }
}
