import AXSwift
import PromiseKit

/// The global Swindler state, lazily initialized.
public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>())

/// An object responsible for propagating the given event. Used internally by the OSX delegates.
protocol EventNotifier: class {
  func notify<Event: EventType>(event: Event)
}

/// Implements StateDelegate using the AXUIElement API.
class OSXStateDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: StateDelegate, EventNotifier {
  typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
  typealias AppDelegate = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>
  private typealias EventHandler = (EventType) -> ()

  private var applications: [AppDelegate] = []
  private var eventHandlers: [String: [EventHandler]] = [:]

  var runningApplications: [ApplicationDelegate] { return applications.map({ $0 as ApplicationDelegate }) }
  var knownWindows: [WindowDelegate] { return applications.flatMap({ $0.knownWindows }) }

  // TODO: fix strong ref cycle
  // TODO: retry instead of ignoring an app/window when timeouts are encountered during initialization?

  init() {
    log.debug("Initializing Swindler")
    for appElement in ApplicationElement.all() {
      AppDelegate.initialize(axElement: appElement, notifier: self).then { application in
        self.applications.append(application)
      }.error { error in
        let pid = try? appElement.pid()
        let bundleID = pid.flatMap{NSRunningApplication(processIdentifier: $0)}.flatMap{$0.bundleIdentifier}
        let pidString = (pid == nil) ? "??" : String(pid!)
        log.notice("Could not watch application \(bundleID ?? "") (pid=\(pidString)): \(error)")
      }
    }
    log.debug("Done initializing")
  }

  func on<Event: EventType>(handler: (Event) -> ()) {
    let notification = Event.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! Event) })
  }

  func notify<Event: EventType>(event: Event) {
    assert(NSThread.currentThread().isMainThread)
    if let handlers = eventHandlers[Event.typeName] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}
