import Foundation
import AVFoundation
import Speech
import OSLog

/// Manages and monitors permission changes for audio and speech recognition
internal actor PermissionManager {
    private static let logger = Logger(subsystem: "com.auralkit", category: "PermissionManager")
    
    /// Current audio permission status
    private var audioPermissionStatus: AVAuthorizationStatus = .notDetermined
    
    /// Current speech recognition permission status  
    private var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    /// Callbacks for permission change notifications
    private var audioPermissionChangeHandlers: [@Sendable (Bool) async -> Void] = []
    private var speechPermissionChangeHandlers: [@Sendable (Bool) async -> Void] = []
    
    /// Monitoring task for permission changes
    private var monitoringTask: Task<Void, Never>?
    
    init() {
        // Initialize current permission states
        Task {
            await updatePermissionStates()
            await startMonitoring()
        }
    }
    
    deinit {
        monitoringTask?.cancel()
    }
    
    /// Register a handler for audio permission changes
    func onAudioPermissionChange(_ handler: @escaping @Sendable (Bool) async -> Void) {
        audioPermissionChangeHandlers.append(handler)
    }
    
    /// Register a handler for speech permission changes
    func onSpeechPermissionChange(_ handler: @escaping @Sendable (Bool) async -> Void) {
        speechPermissionChangeHandlers.append(handler)
    }
    
    /// Check if all required permissions are granted
    func hasRequiredPermissions() async -> Bool {
        await updatePermissionStates()
        return audioPermissionStatus == .authorized && speechPermissionStatus == .authorized
    }
    
    /// Request all required permissions
    func requestPermissions() async throws {
        // Request audio permission
        let audioGranted = await requestAudioPermission()
        if !audioGranted {
            throw AuralError.permissionDenied
        }
        
        // Request speech recognition permission
        let speechGranted = await requestSpeechPermission()
        if !speechGranted {
            throw AuralError.permissionDenied
        }
    }
    
    /// Request audio recording permission
    private func requestAudioPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
    
    /// Request speech recognition permission
    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
    
    /// Update current permission states
    private func updatePermissionStates() async {
        let newAudioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let newSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        
        // Check for audio permission changes
        if newAudioStatus != audioPermissionStatus {
            let oldStatus = audioPermissionStatus
            audioPermissionStatus = newAudioStatus
            
            Self.logger.info("Audio permission changed from \(String(describing: oldStatus)) to \(String(describing: newAudioStatus))")
            
            // Notify handlers
            let isGranted = newAudioStatus == .authorized
            Task {
                await notifyAudioPermissionHandlers(isGranted)
            }
        }
        
        // Check for speech permission changes
        if newSpeechStatus != speechPermissionStatus {
            let oldStatus = speechPermissionStatus
            speechPermissionStatus = newSpeechStatus
            
            Self.logger.info("Speech permission changed from \(String(describing: oldStatus)) to \(String(describing: newSpeechStatus))")
            
            // Notify handlers
            let isGranted = newSpeechStatus == .authorized
            Task {
                await notifySpeechPermissionHandlers(isGranted)
            }
        }
    }
    
    /// Start monitoring for permission changes
    private func startMonitoring() {
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                // Check permissions periodically (every 5 seconds)
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }
                
                await self.updatePermissionStates()
            }
        }
        
        // Also register for app foreground notifications where permission changes might occur
        #if os(iOS)
        Task { @MainActor in
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task {
                    await self?.updatePermissionStates()
                }
            }
        }
        #endif
    }
    
    /// Notify audio permission change handlers
    private func notifyAudioPermissionHandlers(_ isGranted: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for handler in audioPermissionChangeHandlers {
                group.addTask {
                    await handler(isGranted)
                }
            }
        }
    }
    
    /// Notify speech permission change handlers
    private func notifySpeechPermissionHandlers(_ isGranted: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for handler in speechPermissionChangeHandlers {
                group.addTask {
                    await handler(isGranted)
                }
            }
        }
    }
}

