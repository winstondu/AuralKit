import Foundation

/// Protocol defining the interface for speech recognition model management.
///
/// ModelManagerProtocol abstracts the management of speech recognition models,
/// including downloading, installation, and availability checking. This abstraction
/// allows for different implementations including production managers using
/// Apple's AssetInventory and mock implementations for testing.
///
/// ## Model Lifecycle
/// 1. Check if model is available for target language
/// 2. Download model if not available (with progress tracking)
/// 3. Use model for speech recognition
/// 4. Optional: Deallocate models to free space
///
/// ## Storage Management
/// Models are managed by the system and don't count against your app's
/// storage quota. However, there may be limits on the number of concurrent
/// models that can be installed.
///
/// ## Example
/// ```swift
/// let modelManager: ModelManagerProtocol = ProductionModelManager()
/// 
/// if !(await modelManager.isModelAvailable(for: .spanish)) {
///     try await modelManager.downloadModel(for: .spanish)
/// }
/// ```
protocol ModelManagerProtocol: Sendable {
    /// Checks if a speech recognition model is available for the specified language.
    ///
    /// This method verifies that the necessary speech recognition assets
    /// are installed and ready for use with the specified language.
    ///
    /// - Parameter language: The language to check model availability for
    /// - Returns: `true` if the model is available, `false` otherwise
    func isModelAvailable(for language: AuralLanguage) async -> Bool
    
    /// Downloads and installs the speech recognition model for the specified language.
    ///
    /// This method initiates the download and installation of speech recognition
    /// assets for the specified language. The operation may take some time
    /// depending on model size and network connectivity.
    ///
    /// - Parameter language: The language to download the model for
    /// - Throws: AuralError.networkError if download fails, AuralError.unsupportedLanguage if language is not supported
    func downloadModel(for language: AuralLanguage) async throws
    
    /// Gets the download progress for a language model currently being downloaded.
    ///
    /// This method provides progress information for ongoing model downloads,
    /// allowing applications to show progress indicators to users.
    ///
    /// - Parameter language: The language to get download progress for
    /// - Returns: Progress value from 0.0 to 1.0, or `nil` if no download is active
    func getDownloadProgress(for language: AuralLanguage) async -> Double?
    
    /// Gets the list of all supported languages.
    ///
    /// This method returns the complete list of languages that have
    /// speech recognition models available for download and use.
    ///
    /// - Returns: Array of supported AuralLanguage values
    func getSupportedLanguages() async -> [AuralLanguage]
}