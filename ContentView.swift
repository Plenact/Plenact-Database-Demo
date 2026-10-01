// -------------------------------------------------------------------------------------------------
// @file       ContentView.swift
// @brief      Manage the app token and retrieve Plenact API data
// @details    Exercise the public health endpoint and authenticated database bootstrap
//
// @notes      The health test is public; bootstrap retrieval uses the stored app token
//
// @section    Opens
//      Installation-status upload is not integrated yet
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

///
/// Bootstrap endpoint response contract
///
/// @section    Purpose
///     Decode the database-backed configuration and optional active notice
///
private struct BootstrapResponse: Decodable {

    let configuration: AppConfiguration
    let notice:        BootstrapNotice?
    let preferences:   PreferencesSubmission?
}

///
/// Required configuration returned by bootstrap.php
///
private struct AppConfiguration: Decodable {

    let welcomeMessage: String
    let version:        Int

    enum CodingKeys: String, CodingKey {
        case welcomeMessage = "welcome_message"
        case version
    }
}

///
/// Optional active notice returned by bootstrap.php
///
private struct BootstrapNotice: Decodable {

    let id:      Int        /* Notice identifier   */
    let message: String     /* Notice message text */
}


///
/// Preferences sent to preferences.php and read from bootstrap.php
///
private struct PreferencesSubmission: Codable, Equatable {

    let favoriteFood: String        /* User's favorite food             */
    let catCount:     Int           /* Number of cats owned by the user */

    // Coding keys for JSON serialization
    enum CodingKeys: String, CodingKey {
        case favoriteFood = "favorite_food"
        case catCount     = "cat_count"
    }
}


///
/// Successful response returned by preferences.php
///
private struct PreferencesSaveResponse: Decodable {

    let saved: Bool /* Indicates whether the preferences were successfully saved */
}

///
/// Token validation status for the current session
///
private enum TokenValidationStatus {
    case notChecked         /* Token validation has not been performed yet  */
    case accepted           /* Token has been accepted by the server        */
    case rejected           /* Token has been rejected by the server        */
    case forbidden          /* Token is forbidden from accessing the server */
}

///
/// Input fields for the content view
///
private enum ContentField: Hashable {
    case token              /* User's token input field                     */
    case favoriteFood       /* User's favorite food input field             */
    case catCount           /* User's cat count input field                 */
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

    // Variables
    @State private var result            = "Ready to test."               /* Latest request feedback                */
    @State private var isLoading         = false                          /* Request-in-progress flag               */
    @State private var tokenInput        = ""                             /* Token being entered, never logged      */
    @State private var tokenMessage      = ""                             /* Keychain operation feedback            */
    @State private var bootstrapResult   = "Database data not loaded."    /* Latest bootstrap response feedback     */
    @State private var favoriteFoodInput = ""                             /* User's favorite food input field       */
    @State private var catCountInput     = ""                             /* User's cat count input field           */
    @State private var preferencesResult = "Preferences not loaded."     /* Latest preferences feedback           */

    // View State
    @State private var tokenIsStored: Bool?              = nil                                  /* nil means Keychain status is unknown  */
    @State private var tokenValidationStatus             = TokenValidationStatus.notChecked     /* Initial token validation status       */
    @State private var bootstrapData: BootstrapResponse? = nil                                  /* Latest bootstrap response             */
    @State private var savedPreferences: PreferencesSubmission? = nil                           /* Last preferences loaded or saved       */

    // Focus State
    @FocusState private var focusedField: ContentField?                                        /* Currently focused input field         */


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
                        .focused($focusedField, equals: .token)

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

            GroupBox("Database Bootstrap") {

                VStack(alignment: .leading, spacing: 12) {

                    Button("Load Database Data") {

                        Task {
                            await loadBootstrap()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Text(bootstrapResult)
                        .font(.footnote)
                        .textSelection(.enabled)

                    if let bootstrapData {

                        Text(bootstrapData.configuration.welcomeMessage)
                            .font(.body)
                            .textSelection(.enabled)

                        Text("Configuration version: \(bootstrapData.configuration.version)")
                            .font(.footnote)

                        if let notice = bootstrapData.notice {

                            Text("Notice: \(notice.message)")
                                .font(.footnote)
                                .textSelection(.enabled)

                        } else {
                            Text("No active notice.")
                                .font(.footnote)
                        }
                    }
                }
            }

            GroupBox("Installation Preferences") {

                VStack(alignment: .leading, spacing: 12) {

                    HStack {
                        Text("Favorite Food:")
                            .frame(width: 112, alignment: .leading)

                        TextField("Enter a food", text: $favoriteFoodInput)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .favoriteFood)
                            .onChange(of: favoriteFoodInput) { _, _ in
                                updatePreferencesEditStatus()
                            }
                    }

                    if !favoriteFoodInput.isEmpty && !favoriteFoodIsValid {

                        Text("Enter a food name up to 255 characters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("#Cats:")
                            .frame(width: 112, alignment: .leading)

                        TextField("Positive whole number", text: $catCountInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .catCount)
                            .onChange(of: catCountInput) { _, _ in
                                updatePreferencesEditStatus()
                            }
                    }

                    if !catCountInput.isEmpty && catCountValue == nil {

                        Text("Enter a positive whole number.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Preferences") {

                        Task {
                            await savePreferences()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!preferencesInputIsValid || isLoading)

                    Text(preferencesResult)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .toolbar {

            ToolbarItemGroup(placement: .keyboard) {

                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear(perform: loadTokenStatus)
    }


    ///
    /// @brief      Check token format without converting or normalizing its contents
    /// @return     (Bool) true only for 64 ASCII alphanumeric bytes
    ///
    private var tokenInputIsValid: Bool {

        isValidToken(tokenInput)
    }


    ///
    /// @brief      Check the server's required app-token format
    /// 
    /// @param[in]  token - Candidate token to validate without normalization
    /// @return     (Bool) true only for 64 ASCII alphanumeric bytes
    ///
    private func isValidToken(_ token: String) -> Bool {

        let tokenBytes = token.utf8

        return tokenBytes.count == 64 && tokenBytes.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
        }
    }


    ///
    /// @brief      Return the trimmed food value when it fits the API contract
    /// @return     (String) food value without surrounding whitespace
    ///
    private var favoriteFoodValue: String {

        // Trim surrounding whitespace and newlines from the favorite food input before returning it
        favoriteFoodInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @brief      Check whether the food input can be stored in the database column
    /// @return     (Bool) true for a nonempty value of at most 255 Unicode scalars
    ///
    private var favoriteFoodIsValid: Bool {

        // Match the API's Unicode-scalar length limit.
        !favoriteFoodValue.isEmpty && favoriteFoodValue.unicodeScalars.count <= 255
    }


    ///
    /// @brief      Parse and range-check the positive cat count
    /// @return     (Int?) valid MySQL unsigned integer value, or nil
    ///
    private var catCountValue: Int? {

        guard let count = Int(catCountInput),
               count > 0,
              count <= 4_294_967_295 else {

            return nil
        }

        return count
    }


    ///
    /// @brief      Check whether both preference values can be submitted
    /// @return     (Bool) true when the food and positive cat count are valid
    ///
    private var preferencesInputIsValid: Bool {

        // Validate that both the favorite food and cat count inputs meet their respective criteria before allowing submission
        favoriteFoodIsValid && catCountValue != nil
    }


    ///
    /// @brief      Keep preference feedback consistent with the last server state
    /// @details    Programmatic loads match the baseline; user edits differ from it
    ///
    private func updatePreferencesEditStatus() {

        if let savedPreferences,
           favoriteFoodValue == savedPreferences.favoriteFood,
           catCountValue == savedPreferences.catCount {
            preferencesResult = "Preferences loaded from the database."
        } else if savedPreferences == nil
                    && favoriteFoodInput.isEmpty
                    && catCountInput.isEmpty {
            preferencesResult = "No saved preferences for this installation."
        } else {
            preferencesResult = "Unsaved changes."
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

        guard tokenIsStored else {
            return "No token is stored in Keychain."
        }

        switch tokenValidationStatus {

            case .notChecked:
                return "Token is stored in Keychain. Server validation has not been performed this session."

            case .accepted:
                return "Token is stored in Keychain. The server accepted it for app access."

            case .rejected:
                return "Token is stored in Keychain, but the server rejected it (HTTP 401)."

            case .forbidden:
                return "Token is stored in Keychain, but it lacks app access (HTTP 403)."
        }
    }


    ///
    /// @brief      Read only whether a token exists; never place it in the field
    /// @post       tokenIsStored is true, false, or nil when Keychain access fails
    ///
    private func loadTokenStatus() {

        do {
            tokenIsStored         = try TokenStore.load() != nil
            tokenValidationStatus = .notChecked
            tokenMessage          = ""
        } catch {
            tokenIsStored         = nil
            tokenValidationStatus = .notChecked
            tokenMessage          = "Could not read Keychain status: \(error.localizedDescription)"
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
            
            tokenInput            = ""
            tokenIsStored         = true
            tokenValidationStatus = .notChecked
            tokenMessage          = "Token saved to Keychain."
        } catch {
            tokenMessage          = "Could not save token: \(error.localizedDescription)"
        }
    }


    ///
    /// @brief      Delete the stored app token from Keychain
    ///
    private func deleteToken() {

        do {
            try TokenStore.delete()

            tokenIsStored         = false
            tokenValidationStatus = .notChecked
            tokenMessage          = "Stored token deleted from Keychain."

        } catch {
            tokenMessage          = "Could not delete token: \(error.localizedDescription)"
        }
    }


    ///
    /// @fcn        ContentView.savePreferences
    /// @brief      Submit validated installation preferences to the protected API
    /// @details    The server associates the update with its configured installation ID
    ///
    /// @return     (Void) updates the save status without displaying the credential
    /// @post       isLoading is false on every completion path
    ///
    private func savePreferences() async {

        guard preferencesInputIsValid,

              let catCount = catCountValue else {

            preferencesResult = "Enter a food name and a positive whole number of cats."
            return
        }

        // Begin the process of saving preferences
        isLoading         = true
        preferencesResult = "Saving preferences…"

        defer { isLoading = false }

        let token: String

        do {
            guard let storedToken = try TokenStore.load() else {

                preferencesResult = "No app token is stored. Save the app token before submitting preferences."
                return
            }

            guard isValidToken(storedToken) else {

                preferencesResult = "The stored token has an invalid format. Replace it before continuing."
                return
            }

            token = storedToken
        } catch {

            preferencesResult = "Could not read the app token from Keychain: \(error.localizedDescription)"
            return
        }

        guard let url = URL(string: "https://plenact.com/api-dev/preferences.php") else {

            preferencesResult = "Invalid preferences API URL."
            return
        }

        var request = URLRequest(url: url)

        request.httpMethod      = "POST"
        request.timeoutInterval = 20
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let submission = PreferencesSubmission(
            favoriteFood: favoriteFoodValue,
            catCount:     catCount
        )

        do {
            request.httpBody = try JSONEncoder().encode(submission)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {

                preferencesResult = "Failed: preferences response was not HTTP."
                return
            }

            switch httpResponse.statusCode {

                case 200:                                           /* OK */
                    tokenValidationStatus = .accepted

                    let result = try JSONDecoder().decode(
                        PreferencesSaveResponse.self,
                        from: data
                    )

                    guard result.saved else {

                        preferencesResult = "The server did not confirm that preferences were saved."
                        return
                    }

                    preferencesResult = "Preferences saved to the database for this installation."
                    savedPreferences = submission

                case 401:                                           /* Unauthorized */
                    tokenValidationStatus = .rejected
                    preferencesResult     = "Authentication failed (HTTP 401). The stored app token was rejected."

                case 403:                                           /* Forbidden */
                    tokenValidationStatus = .forbidden
                    preferencesResult     = "Access denied (HTTP 403). This endpoint requires the app token."

                case 400, 413, 415, 422:                            /* Client errors */
                    preferencesResult     = "The server rejected the preference values (HTTP \(httpResponse.statusCode))."

                case 500...599:                                     /* Server errors */
                    preferencesResult     = "Server error (HTTP \(httpResponse.statusCode)). Try again later."

                default:
                    preferencesResult     = "Preferences request failed with HTTP \(httpResponse.statusCode)."
            }
        } catch is DecodingError {
            preferencesResult = "Could not decode the preferences response. Its JSON does not match the expected format."

        } catch let error as URLError {

            switch error.code {

                case .notConnectedToInternet, .networkConnectionLost:               /* Network unavailable */
                    preferencesResult = "Network unavailable. Check the connection and try again."

                case .timedOut:                                                     /* Request timed out */
                    preferencesResult = "The preferences request timed out. Try again."

                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:       /* Host unreachable */
                    preferencesResult = "Could not reach the API host. Check the connection and try again."

                default:
                    preferencesResult = "Network request failed: \(error.localizedDescription)"
            }
        } catch {
            preferencesResult = "Preferences request failed: \(error.localizedDescription)"
        }
    }


    ///
    /// @fcn        ContentView.loadBootstrap
    /// @brief      Fetch authenticated configuration and the optional active notice
    /// @details    Load the app token from Keychain, require HTTP 200, and decode the response
    ///
    /// @return     (Void) updates bootstrap data or a safe failure message
    /// @post       isLoading is false and no credential is included in UI feedback
    ///
    private func loadBootstrap() async {

        isLoading       = true
        bootstrapData   = nil
        bootstrapResult = "Loading database data…"

        defer { isLoading = false }

        let token: String

        do {
            guard let storedToken = try TokenStore.load() else {

                bootstrapResult = "No app token is stored. Save the app token before loading database data."
                
                return
            }

            guard isValidToken(storedToken) else {

                bootstrapResult = "The stored token has an invalid format. Replace it before continuing."
               
                return
            }

            token = storedToken

        } catch {

            bootstrapResult = "Could not read the app token from Keychain: \(error.localizedDescription)"
           
            return
        }

        guard let url = URL(

            string: "https://plenact.com/api-dev/bootstrap.php"

        ) else {

            bootstrapResult = "Invalid bootstrap API URL."

            return
        }

        var request             = URLRequest(url: url)
        request.httpMethod      = "GET"
        request.timeoutInterval = 20
        request.cachePolicy     = .reloadIgnoringLocalCacheData

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {

                bootstrapResult = "Failed: bootstrap response was not HTTP."

                return
            }

            switch httpResponse.statusCode {

                case 200:                                               /* HTTP 200: OK */
                    tokenValidationStatus = .accepted
                    break

                case 401:                                               /* HTTP 401: Unauthorized */                    

                    tokenValidationStatus = .rejected
                    bootstrapResult = "Authentication failed (HTTP 401). The stored app token was rejected."
                    
                    return

                case 403:                                               /* HTTP 403: Forbidden */

                    tokenValidationStatus = .forbidden
                    bootstrapResult = "Access denied (HTTP 403). This endpoint requires the app token."
                    
                    return

                case 500...599:                                         /* HTTP 5xx: Server Error */

                    bootstrapResult = "Server error (HTTP \(httpResponse.statusCode)). Try again later."
                    
                    return

                default:

                    bootstrapResult = "Bootstrap request failed with HTTP \(httpResponse.statusCode)."
                    
                    return

            }

            let loadedData = try JSONDecoder().decode(BootstrapResponse.self, from: data)

            bootstrapData = loadedData

            if let preferences = loadedData.preferences {

                savedPreferences  = preferences                                     /* Save the loaded preferences            */
                favoriteFoodInput = preferences.favoriteFood                        /* Populate the favorite food input field */
                catCountInput     = String(preferences.catCount)                    /* Populate the cat count input field     */
                preferencesResult = "Preferences loaded from the database."

            } else {

                savedPreferences  = nil                                             /* Clear the saved preferences            */
                favoriteFoodInput = ""                                              /* Clear the favorite food input field    */                   
                catCountInput     = ""                                              /* Clear the cat count input field        */
                preferencesResult = "No saved preferences for this installation."   /* Clear the preferences input fields     */
            }

            bootstrapResult = "Database data loaded successfully."

        } catch is DecodingError {

            bootstrapResult = "Could not decode the bootstrap response. Its JSON does not match the expected format."
       
        } catch let error as URLError {

            switch error.code {

                case .notConnectedToInternet, .networkConnectionLost:

                    bootstrapResult = "Network unavailable. Check the connection and try again."
                
                case .timedOut:
                 
                    bootstrapResult = "The bootstrap request timed out. Try again."
               
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
               
                    bootstrapResult = "Could not reach the API host. Check the connection and try again."
              
                default:
               
                    bootstrapResult = "Network request failed: \(error.localizedDescription)"
            }
        } catch {

            bootstrapResult = "Bootstrap request failed: \(error.localizedDescription)"
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
