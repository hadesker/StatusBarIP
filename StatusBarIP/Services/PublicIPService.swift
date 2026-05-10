import Foundation

protocol PublicIPFetching: Sendable {
    func fetch() async throws -> PublicIPResponse
}

struct PublicIPService: PublicIPFetching {
    private let endpoint = URL(string: "https://ip.faster.asia/?json=true")!

    func fetch() async throws -> PublicIPResponse {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(PublicIPResponse.self, from: data)
    }
}
