import Foundation

/// Alert-rule collection helpers. Extracted from AppSettings.swift
/// (Phase 1.1 of Docs/hardening-plan.md); `alertRules` storage, its didSet,
/// and the persist/decode plumbing stay in the core file.
extension AppSettings {

    func addRule(_ category: AlertCategory) {
        alertRules.append(.new(category))
    }

    func removeRule(_ id: UUID) {
        alertRules.removeAll { $0.id == id }
    }

    func resetRules() {
        alertRules = BatteryAlertRule.defaults
    }
}
