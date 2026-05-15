import SwiftUI

extension EnvironmentValues {
    @Entry var processRunner: any ProcessRunning = ProductionProcessRunner()
}
