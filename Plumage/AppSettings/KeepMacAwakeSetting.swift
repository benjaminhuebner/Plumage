// Caseless namespace for the @AppStorage key — mirrors AppAppearance, but the
// choice is one boolean, not an enum of options.
nonisolated enum KeepMacAwakeSetting {
    static let storageKey = "keepMacAwakeDuringSession"
    static let defaultValue = false
}
