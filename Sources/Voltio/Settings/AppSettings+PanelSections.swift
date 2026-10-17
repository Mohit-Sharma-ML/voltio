import Foundation

/// Panel card-group ordering: the user's drag order plus helpers to move
/// sections and restore defaults. Extracted from AppSettings.swift
/// (Phase 1.1 of Docs/hardening-plan.md); `panelSectionOrder` storage and its
/// didSet stay in the core file.
extension AppSettings {

    /// The panel's sections in display order: the user's stored order first
    /// (drag to reorder in Settings → Menu Bar), then any sections missing
    /// from it — so a section added in an app update still shows up.
    var orderedPanelSections: [PanelSection] {
        let stored = panelSectionOrder
        let missing = PanelSection.allCases.filter { !stored.contains($0) }
        return stored.filter { PanelSection.allCases.contains($0) } + missing
    }

    /// Moves `section` up one slot in the stored order (no-op at the top).
    func movePanelSectionUp(_ section: PanelSection) {
        movePanelSection(section, offset: -1)
    }

    /// Moves `section` down one slot in the stored order (no-op at the end).
    func movePanelSectionDown(_ section: PanelSection) {
        movePanelSection(section, offset: +1)
    }

    private func movePanelSection(_ section: PanelSection, offset: Int) {
        var order = orderedPanelSections
        guard let index = order.firstIndex(of: section) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        panelSectionOrder = order
    }

    /// Restores the default section order (Battery Information first).
    func resetPanelSectionOrder() {
        panelSectionOrder = PanelSection.allCases
    }
}
