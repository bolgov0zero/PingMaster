import Foundation

class HTTPChecker {
    static func check(host: String, method: PollMethod, completion: @escaping (Double?) -> Void) {
        var urlString = host
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            let scheme = method == .https ? "https" : "http"
            urlString = "\(scheme)://\(urlString)"
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"

        let start = Date()
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...599).contains(http.statusCode) else {
                completion(nil)
                return
            }
            completion(Date().timeIntervalSince(start) * 1000)
        }.resume()
    }
}
