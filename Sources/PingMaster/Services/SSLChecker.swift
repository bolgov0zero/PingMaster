import Foundation
import Network
import Security

// Connects over TLS and reads the leaf certificate's expiry date.
// We accept the certificate regardless of validity — the goal is only to
// inspect its notAfter, not to enforce trust.
enum SSLChecker {
    static func check(host: String, completion: @escaping (Date?) -> Void) {
        var hostname = host
        var port: UInt16 = 443

        for scheme in ["https://", "http://"] {
            if hostname.hasPrefix(scheme) {
                hostname = String(hostname.dropFirst(scheme.count)); break
            }
        }
        if let slash = hostname.firstIndex(of: "/") {
            hostname = String(hostname[..<slash])
        }
        if let colon = hostname.lastIndex(of: ":"),
           let p = UInt16(hostname[hostname.index(after: colon)...]) {
            port = p
            hostname = String(hostname[..<colon])
        }

        guard !hostname.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil); return
        }

        let queue = DispatchQueue(label: "ssl.check", qos: .utility)
        var captured: Date?

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, trustRef, complete in
                let secTrust = sec_trust_copy_ref(trustRef).takeRetainedValue()
                captured = leafExpiry(secTrust)
                complete(true) // accept — we only want to read the cert
            },
            queue
        )

        let params = NWParameters(tls: tls)
        let connection = NWConnection(host: NWEndpoint.Host(hostname), port: nwPort, using: params)

        var done = false
        func finish(_ date: Date?) {
            guard !done else { return }
            done = true
            connection.cancel()
            completion(date)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:            finish(captured)
            case .failed, .cancelled: finish(captured)
            default: break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 6) { finish(captured) }
    }

    private static func leafExpiry(_ trust: SecTrust) -> Date? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }

        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(leaf, keys, nil) as? [CFString: Any],
              let notAfter = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let seconds = notAfter[kSecPropertyKeyValue] as? Double else { return nil }

        // The value is seconds since the reference date (2001-01-01).
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
