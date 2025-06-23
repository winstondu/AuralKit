@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Monitors audio hardware changes and notifies when audio routes change
internal actor AudioHardwareMonitor {
  private static let logger = Logger(subsystem: "com.auralkit", category: "AudioHardwareMonitor")

  /// Callbacks for audio hardware change notifications
  private var hardwareChangeHandlers: [@Sendable (AudioHardwareChange) async -> Void] = []

  #if os(iOS) || os(tvOS)
    /// Current audio route
    private var currentRoute: AVAudioSessionRouteDescription?
  #endif

  /// Observation tokens for notifications
  private var notificationObservers: [NSObjectProtocol] = []

  /// Types of audio hardware changes
  enum AudioHardwareChange {
    #if os(iOS) || os(tvOS)
      case routeChanged(old: AVAudioSessionRouteDescription?, new: AVAudioSessionRouteDescription)
    #else
      case routeChanged
    #endif
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case mediaServicesReset
    case silenceSecondaryAudioHint(begin: Bool)
  }

  init() {
    Task {
      await setupNotifications()
    }
  }

  deinit {
    // Cleanup is handled by the system when observers are deallocated
    // We can't access actor-isolated state from deinit
  }

  /// Register a handler for audio hardware changes
  func onHardwareChange(_ handler: @escaping @Sendable (AudioHardwareChange) async -> Void) {
    hardwareChangeHandlers.append(handler)
  }

  /// Set up notification observers for audio hardware changes
  private func setupNotifications() {
    #if os(iOS) || os(tvOS)
      let audioSession = AVAudioSession.sharedInstance()
      currentRoute = audioSession.currentRoute

      // Route change notification
      let routeChangeObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: audioSession,
        queue: nil
      ) { notification in
        // Extract needed data immediately to avoid concurrency issues
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let previousRoute =
          notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
          as? AVAudioSessionRouteDescription

        Task { [weak self] in
          await self?.handleRouteChange(reasonValue: reasonValue, previousRoute: previousRoute)
        }
      }
      notificationObservers.append(routeChangeObserver)

      // Interruption notification
      let interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: audioSession,
        queue: nil
      ) { notification in
        // Extract needed data immediately to avoid concurrency issues
        let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

        Task { [weak self] in
          await self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
        }
      }
      notificationObservers.append(interruptionObserver)

      // Media services reset notification
      let mediaServicesResetObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: audioSession,
        queue: nil
      ) { notification in
        Task { [weak self] in
          await self?.handleMediaServicesReset()
        }
      }
      notificationObservers.append(mediaServicesResetObserver)

      // Silence secondary audio hint notification
      let silenceSecondaryObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.silenceSecondaryAudioHintNotification,
        object: audioSession,
        queue: nil
      ) { notification in
        // Extract needed data immediately to avoid concurrency issues
        let typeValue =
          notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt

        Task { [weak self] in
          await self?.handleSilenceSecondaryAudioHint(typeValue: typeValue)
        }
      }
      notificationObservers.append(silenceSecondaryObserver)
    #endif
  }

  /// Handle audio route changes
  #if os(iOS) || os(tvOS)
  private func handleRouteChange(reasonValue: UInt?, previousRoute: AVAudioSessionRouteDescription?)
    async
  {
      guard let reasonValue = reasonValue,
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
      else {
        return
      }

      let audioSession = AVAudioSession.sharedInstance()
      let newRoute = audioSession.currentRoute

      Self.logger.info("Audio route changed: \(reason.debugDescription)")
      Self.logger.debug("Old route: \(String(describing: previousRoute)), New route: \(newRoute)")

      // Update current route
      let oldRoute = currentRoute
      currentRoute = newRoute

      // Notify handlers
      await notifyHandlers(.routeChanged(old: oldRoute, new: newRoute))

      // Log specific reasons that might affect recording
      switch reason {
      case .oldDeviceUnavailable:
        Self.logger.warning("Previous audio device became unavailable")
      case .newDeviceAvailable:
        Self.logger.info("New audio device became available")
      case .override:
        Self.logger.info("Audio route was overridden")
      case .wakeFromSleep:
        Self.logger.info("Device woke from sleep")
      case .noSuitableRouteForCategory:
        Self.logger.error("No suitable audio route for current category")
      default:
        break
      }
  }
  #endif

  /// Handle audio interruptions
  #if os(iOS) || os(tvOS)
  private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) async {
      guard let typeValue = typeValue,
        let type = AVAudioSession.InterruptionType(rawValue: typeValue)
      else {
        return
      }

      switch type {
      case .began:
        Self.logger.warning("Audio interruption began")
        await notifyHandlers(.interruptionBegan)

      case .ended:
        Self.logger.info("Audio interruption ended")

        // Check if we should resume
        var shouldResume = false
        if let optionsValue = optionsValue {
          let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
          shouldResume = options.contains(.shouldResume)
        }

        await notifyHandlers(.interruptionEnded(shouldResume: shouldResume))

      @unknown default:
        Self.logger.warning("Unknown interruption type: \(typeValue)")
      }
  }
  #endif

  /// Handle media services reset
  private func handleMediaServicesReset() async {
    Self.logger.error("Media services were reset - audio system needs to be reconfigured")
    await notifyHandlers(.mediaServicesReset)
  }

  /// Handle silence secondary audio hint
  #if os(iOS) || os(tvOS)
  private func handleSilenceSecondaryAudioHint(typeValue: UInt?) async {
      guard let typeValue = typeValue,
        let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue)
      else {
        return
      }

      switch type {
      case .begin:
        Self.logger.info("Should silence secondary audio")
        await notifyHandlers(.silenceSecondaryAudioHint(begin: true))

      case .end:
        Self.logger.info("Can resume secondary audio")
        await notifyHandlers(.silenceSecondaryAudioHint(begin: false))

      @unknown default:
        Self.logger.warning("Unknown silence secondary audio hint type: \(typeValue)")
      }
  }
  #endif

  /// Notify all registered handlers of a hardware change
  private func notifyHandlers(_ change: AudioHardwareChange) async {
    await withTaskGroup(of: Void.self) { group in
      for handler in hardwareChangeHandlers {
        group.addTask {
          await handler(change)
        }
      }
    }
  }
}

// Extension to add debug descriptions
#if os(iOS) || os(tvOS)
  extension AVAudioSession.RouteChangeReason {
    var debugDescription: String {
      switch self {
      case .unknown: return "unknown"
      case .newDeviceAvailable: return "newDeviceAvailable"
      case .oldDeviceUnavailable: return "oldDeviceUnavailable"
      case .categoryChange: return "categoryChange"
      case .override: return "override"
      case .wakeFromSleep: return "wakeFromSleep"
      case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
      case .routeConfigurationChange: return "routeConfigurationChange"
      @unknown default: return "unknown(\(rawValue))"
      }
    }
  }
#endif
