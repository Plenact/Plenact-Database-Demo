// -------------------------------------------------------------------------------------------------
// @file       MyApp.swift
// @brief      Launch the Plenact Database Demo application
// @details    Create the main window and display the API test view
//
// @author     Justin Reina
// @created    Not recorded in the original file
// @last rev   9/30/26
//
// @notes      App entry remains separate from networking and credential storage
//
// @section    Opens
//      Authenticated configuration retrieval and token-entry UI are not integrated yet
//
// -------------------------------------------------------------------------------------------------
import SwiftUI


// --------------------------------------- MARK: - Entry Point ---------------------------------- //

///
/// SwiftUI application entry point
///
/// @section    Purpose
///     Establish the scene that hosts ContentView
///

@main
struct MyApp: App {

    ///
    /// @fcn        MyApp.body
    /// @brief      Construct the main application scene
    ///
    /// @return     (some Scene) window group containing ContentView
    ///
    var body: some Scene {
        
        WindowGroup {
            ContentView()
        }
    }
}
