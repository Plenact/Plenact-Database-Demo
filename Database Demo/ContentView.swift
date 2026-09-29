/**
 A simple SwiftUI view to test the Plenact API health endpoint.

Here’s how the pieces fit:
- HealthResponse defines the expected JSON contract. Decodable lets Swift decode service and ok into typed 
  properties.
- @State holds the displayed result and loading flag. SwiftUI updates the screen when these change.
- @MainActor keeps UI state changes on the main actor.
- Task and await let the button start asynchronous work. Waiting for the network suspends that task without 
  blocking the interface.
- URLRequest specifies GET, a request timeout, and bypassing the local response cache.
- URLSession performs the HTTPS request using native Apple networking.
- The status check distinguishes HTTP success from a completed transfer carrying an error.
- do/catch and defer display networking/decoding failures and always reset the loading state.
  The URL is public information, so it belongs in the code; there are no credentials here. The previous playground 
  scratch block is unnecessary for this screen.
*/
import SwiftUI
import Foundation


private struct HealthResponse: Decodable {
    let service: String
    let ok: Bool
}

@MainActor
struct ContentView: View {
    @State private var result    = "Ready to test."
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Plenact API Test")
                .font(.title)

            Button("Test API") {
                Task {
                    await testAPI()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if isLoading {
                ProgressView("Contacting server…")
            }

            Text(result)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding()
    }

    private func testAPI() async {
        isLoading = true
        result = "Waiting for response…"
        defer { isLoading = false }

        guard let url = URL(
            string: "https://plenact.com/api-dev/health.php"
        ) else {
            result = "Invalid API URL."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                result = "Failed: response was not HTTP."
                return
            }

            guard httpResponse.statusCode == 200 else {
                result = "Server returned HTTP \(httpResponse.statusCode)."
                return
            }

            let health = try JSONDecoder().decode(
                HealthResponse.self,
                from: data
            )

            if health.ok {
                result = "Success: \(health.service) responded."
            } else {
                result = "Server responded, but reported ok = false."
            }
        } catch {
            result = "Request failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}