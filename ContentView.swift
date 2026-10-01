// -------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Manage the app token and exercise the public Plenact health endpoint
// @details    Store credentials in Keychain and present health-request feedback
//
// @notes      This foreground test does not authenticate or access database records
//
// @section    Opens
//      Authenticated configuration retrieval is not integrated yet
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

    @State private var result       = "Ready to test."  /* Latest request feedback              */
    @State private var isLoading    = false             /* Request-in-progress flag             */
    @State private var tokenInput   = ""                /* Token being entered, never logged    */
    @State private var tokenMessage = ""                /* Keychain operation feedback          */
    @State private var tokenIsStored: Bool?             /* nil means Keychain status is unknown */

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

            GroupBox("App Token") {

                VStack(alignment: .leading, spacing: 12) {

                    SecureField("64-character app token", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !tokenInput.isEmpty && !tokenInputIsValid {

                        Text("Enter exactly 64 ASCII letters or digits.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {

                        Button("Save Token", action: saveToken)
                            .buttonStyle(.borderedProminent)
                            .disabled(!tokenInputIsValid)

                        Button("Delete Token", role: .destructive, action: deleteToken)
                            .disabled(tokenIsStored != true)
                    }

                    Text(tokenStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !tokenMessage.isEmpty {

                        Text(tokenMessage)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }

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
        .onAppear(perform: loadTokenStatus)
    }


    ///
    /// @brief      Check token format without converting or normalizing its contents
    /// @return     (Bool) true only for 64 ASCII alphanumeric bytes
    ///
    private var tokenInputIsValid: Bool {

        let tokenBytes = tokenInput.utf8

        return tokenBytes.count == 64 && tokenBytes.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
        }
    }


    ///
    /// @brief      Describe whether a token is stored without revealing its value
    /// @return     (String) non-sensitive Keychain status for the token panel
    ///
    private var tokenStatusMessage: String {

        guard let tokenIsStored else {
            return "Keychain status unavailable."
        }

        return tokenIsStored
            ? "Token is stored in Keychain. Server validation has not been performed."
            : "No token is stored in Keychain."
    }


    ///
    /// @brief      Read only whether a token exists; never place it in the field
    /// @post       tokenIsStored is true, false, or nil when Keychain access fails
    ///
    private func loadTokenStatus() {

        do {
            tokenIsStored = try TokenStore.load() != nil
            tokenMessage  = ""
        } catch {
            tokenIsStored = nil
            tokenMessage  = "Could not read Keychain status: \(error.localizedDescription)"
        }
    }


    ///
    /// @brief      Save a format-checked app token to Keychain
    /// @note       Local storage does not validate the token with the server
    ///
    private func saveToken() {

        guard tokenInputIsValid else {

            tokenMessage = "Enter exactly 64 ASCII letters or digits."

            return
        }

        do {
            try TokenStore.save(tokenInput)
            
            tokenInput    = ""
            tokenIsStored = true
            tokenMessage  = "Token saved to Keychain. Server validation has not been performed."
        } catch {
            tokenMessage  = "Could not save token: \(error.localizedDescription)"
        }
    }


    ///
    /// @brief      Delete the stored app token from Keychain
    ///
    private func deleteToken() {

        do {
            try TokenStore.delete()

            tokenIsStored = false
            tokenMessage  = "Stored token deleted from Keychain."

        } catch {
            tokenMessage = "Could not delete token: \(error.localizedDescription)"
        }
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
