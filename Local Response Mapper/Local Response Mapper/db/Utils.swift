//
//  DbObjectMethods.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import Foundation
import SwiftUI

struct Utils {
    
    static func getHost(_ from: String) -> String? {
        URL(string: from)?.host()
    }
    
    static func getPath(_ from: String) -> String? {
        URL(string: from)?.path()
    }
    
    static func getStatusColor(_ status: Int) -> Color {
        switch status {
        case 100...199: // Informational
            return Color.blue
        case 200...299: // Success
            return Color.green
        case 300...399: // Redirection
            return Color.orange
        case 400...499: // Client Error
            return Color.yellow
        case 500...599: // Server Error
            return Color.red
        default: // Unknown status
            return Color.gray
        }
    }
    
    static func prettyPrintJSON(from jsonString: String) throws -> String {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return jsonString
        }
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        
        return String(data: prettyData, encoding: .utf8) ?? jsonString
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
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                // Check interface name:
                // wifi = ["en0"]
                // wired = ["en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]
                
                let name = String(cString: interface.ifa_name)
                if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {

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
