import Foundation
import Network

struct JoinPayload: Equatable, Sendable {
    static let scheme = "motion-badminton"
    static let version = 1

    let host: String
    let port: UInt16
    let sessionID: UInt64
    let pairingSecret: Data
    let expiresUnixSeconds: UInt64

    enum ValidationError: String, Error, Equatable {
        case invalidCode = "This is not a Motion Badminton pairing code."
        case unsupportedVersion = "The host uses an unsupported pairing-code version."
        case invalidAddress = "The pairing code contains an invalid host address."
        case invalidPort = "The pairing code contains an invalid network port."
        case invalidCredential = "The pairing code is damaged or altered."
        case expired = "This pairing code has expired. Ask the host for a new code."
    }

    static func parse(_ rawValue: String, nowUnixSeconds: UInt64? = nil) throws -> JoinPayload {
        guard let components = URLComponents(string: rawValue),
              components.scheme == scheme,
              components.host == "join"
        else { throw ValidationError.invalidCode }
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        guard Int(values["v"] ?? "") == version else {
            throw ValidationError.unsupportedVersion
        }
        guard let host = values["host"], IPv4Address(host) != nil else {
            throw ValidationError.invalidAddress
        }
        guard let rawPort = UInt16(values["port"] ?? ""), rawPort > 0 else {
            throw ValidationError.invalidPort
        }
        guard let sessionID = UInt64(values["session"] ?? "", radix: 16), sessionID != 0,
              let secret = Data(strictHex: values["secret"] ?? ""), secret.count == 16,
              let expiry = UInt64(values["expires"] ?? ""), expiry > 0
        else { throw ValidationError.invalidCredential }
        let now = nowUnixSeconds ?? UInt64(Date().timeIntervalSince1970)
        guard expiry > now else { throw ValidationError.expired }
        return JoinPayload(
            host: host,
            port: rawPort,
            sessionID: sessionID,
            pairingSecret: secret,
            expiresUnixSeconds: expiry
        )
    }
}

private extension Data {
    init?(strictHex value: String) {
        guard value.count.isMultiple(of: 2),
              value.allSatisfy({ $0.isHexDigit })
        else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
