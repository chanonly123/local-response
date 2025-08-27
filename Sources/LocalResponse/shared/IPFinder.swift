import Foundation

class IPFinder {

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 2
        sessionConfig.timeoutIntervalForResource = 2
        let session = URLSession(configuration: sessionConfig)
        return session
    }()

    static func isServerRunning(urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    static func findWorkingIP(baseIP: String, port: Int, path: String = "/") async -> String? {
        let prefix = baseIP.split(separator: ".").dropLast().joined(separator: ".") // "192.168.31"


        // helper: check one IP
        func checkIP(_ ip: String) async -> String? {
            guard let url = URL(string: "http://\(ip):\(port)\(path)") else { return nil }
            do {
                let (_, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return ip
                }
            } catch {
                return nil
            }
            return nil
        }

        // 0 is network address, 1 is router address, 255 is broadcast address
        let ips = (2...254).map { "\(prefix).\($0)" }

        // scan in batches of 20
        for batchStart in stride(from: 0, to: ips.count, by: 20) {
            let batch = ips[batchStart..<min(batchStart+20, ips.count)]

            if let found = await withTaskGroup(
                of: String?.self,
                returning: String?.self,
                body: { group in
                    for ip in batch {
                        group.addTask {
                            return await checkIP(ip)
                        }
                    }

                    for await result in group {
                        if let working = result {
                            group.cancelAll()
                            return working
                        }
                    }
                    return nil
                }
            ) {
                return found
            }
        }

        return nil
    }
    static func getIPAddress() -> String? {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if
                addrFamily == UInt8(AF_INET)
            //                || addrFamily == UInt8(AF_INET6)
            {

                // Check interface name:
                // wifi = ["en0"]
                // wired = ["en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

                let name = String(cString: interface.ifa_name)
                if
                    name == "en0" || name == "en2" || name == "en3" || name == "en4"
                //                    || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3"
                {

                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
    }
}
