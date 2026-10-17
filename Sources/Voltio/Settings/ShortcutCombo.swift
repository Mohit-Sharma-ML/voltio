import Carbon.HIToolbox

/// A global-shortcut key binding: a virtual key code plus Carbon modifier
/// flags (e.g. `shiftKey | cmdKey`). Persisted as two Ints in `UserDefaults`
/// so Settings can offer "Reset to default shortcuts" without custom decode.
struct ShortcutCombo: Codable, Hashable {
    var keyCode: Int
    var modifiers: Int

    /// Human-readable rendering like "⇧⌘I" for the Settings rows.
    var display: String {
        var out = ""
        if modifiers & Int(controlKey) != 0 { out += "⌃" }
        if modifiers & Int(optionKey) != 0 { out += "⌥" }
        if modifiers & Int(shiftKey) != 0 { out += "⇧" }
        if modifiers & Int(cmdKey) != 0 { out += "⌘" }
        out += Self.keyGlyph(keyCode)
        return out
    }

    /// Maps virtual key codes for letters/digits to their glyphs; anything
    /// else falls back to a bare code so unknown bindings still render.
    private static func keyGlyph(_ keyCode: Int) -> String {
        switch keyCode {
        case Int(kVK_ANSI_A): return "A"
        case Int(kVK_ANSI_B): return "B"
        case Int(kVK_ANSI_C): return "C"
        case Int(kVK_ANSI_D): return "D"
        case Int(kVK_ANSI_E): return "E"
        case Int(kVK_ANSI_F): return "F"
        case Int(kVK_ANSI_G): return "G"
        case Int(kVK_ANSI_H): return "H"
        case Int(kVK_ANSI_I): return "I"
        case Int(kVK_ANSI_J): return "J"
        case Int(kVK_ANSI_K): return "K"
        case Int(kVK_ANSI_L): return "L"
        case Int(kVK_ANSI_M): return "M"
        case Int(kVK_ANSI_N): return "N"
        case Int(kVK_ANSI_O): return "O"
        case Int(kVK_ANSI_P): return "P"
        case Int(kVK_ANSI_Q): return "Q"
        case Int(kVK_ANSI_R): return "R"
        case Int(kVK_ANSI_S): return "S"
        case Int(kVK_ANSI_T): return "T"
        case Int(kVK_ANSI_U): return "U"
        case Int(kVK_ANSI_V): return "V"
        case Int(kVK_ANSI_W): return "W"
        case Int(kVK_ANSI_X): return "X"
        case Int(kVK_ANSI_Y): return "Y"
        case Int(kVK_ANSI_Z): return "Z"
        default: return String(keyCode)
        }
    }
}

