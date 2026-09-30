// -------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Display and exercise the public Plenact health endpoint
// @details    Decode the JSON response and present request progress, success, or failure
//
// @notes      This foreground test does not authenticate or access database records
//
// @section    Opens
//      Authenticated configuration retrieval and token-entry UI are not integrated yet
//
// -------------------------------------------------------------------------------------------------
import SwiftUI
import Foundation


// --------------------------------------- MARK: - Models --------------------------------------- //

///
/// Health endpoint response contract
///
/// @section    Purpose
///     Decode the service identifier and health flag returned by health.php
///
private struct HealthResponse: Decodable {

    let service: String    /* Server-provided service identifier */
    let ok:      Bool      /* Health flag reported by the script */
}

// --------------------------------------- MARK: - View ----------------------------------------- //

///
/// Foreground presentation and request handling for the API test
///
/// @section    Purpose
///     Keep request feedback visible and prevent repeated taps while a request is pending
///
/// @note   UI state is isolated to the main actor; awaiting networking does not block the UI
///
@MainActor
struct ContentView: View {

    @State private var result    = "Ready to test."  /* Latest request feedback */
    @State private var isLoading = false             /* Request-in-progress flag */

    ///
    /// @fcn        ContentView.body
    /// @brief      Render the test button, progress indicator, and result
    /// @details    The button starts an asynchronous task and is disabled during the request
    ///
    /// @return     (some View) current screen content
    ///
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

    ///
    /// @fcn        ContentView.testAPI
    /// @brief      Fetch and decode the public health response
    /// @details    Require HTTP 200 before decoding; display transport, HTTP, and decoding failures
    ///
    /// @return     (Void) updates the view state in place
    ///
    /// @pre        Invoked on the main actor
    /// @post       isLoading is false and result describes the completed attempt
    ///
    /// @note   This request contains no credentials and does not query the database
    ///
    private func testAPI() async {

        isLoading = true                       /* Begin request feedback */
        result    = "Waiting for response…"
        
        defer { isLoading = false }            /* Restore controls on every exit path */

        guard let url = URL(
            
            string: "https://plenact.com/api-dev/health.php"
            
        ) else {
            
            result = "Invalid API URL."
            
            return
        }

        // Configure an explicit foreground GET request.
        var request = URLRequest(url: url)
        
        request.httpMethod      = "GET"
        request.timeoutInterval = 20
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                
                result = "Failed: response was not HTTP."
                
                return
            }

            // A completed transfer can still carry an HTTP error.
            guard httpResponse.statusCode == 200 else {
                
                result = "Server returned HTTP \(httpResponse.statusCode)."
                
                return
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)

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

// --------------------------------------- MARK: - Preview -------------------------------------- //

#Preview {
    ContentView()
}
