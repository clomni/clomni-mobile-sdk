// SwiftPM builds ClomniProtocol and ClomniCore as modules of their own; CocoaPods compiles every file under
// ios/Sources into the single ClomniMessenger module, where there is nothing to import.
#if canImport(ClomniCore)
@_exported import ClomniProtocol
@_exported import ClomniCore
#endif
