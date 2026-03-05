import AppKit
import Combine

/// Thread-safe (MainActor) observable store for terminal output.
/// Parses basic ANSI color escape codes and maintains an NSAttributedString buffer.
@MainActor
public final class TerminalStore: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var text: NSAttributedString = NSAttributedString()

    // MARK: - Styling constants

    private static let defaultTextColor = NSColor(
        red: 0xD4 / 255.0,
        green: 0xD4 / 255.0,
        blue: 0xD4 / 255.0,
        alpha: 1.0
    )

    private static let terminalFont: NSFont = {
        NSFont(name: "SF Mono", size: 11)
            ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }()

    // MARK: - ANSI color table

    /// Maps ANSI SGR foreground codes to AppKit colors.
    private static let ansiColors: [Int: NSColor] = [
        30: .black,
        31: NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1),  // red
        32: NSColor(red: 0.33, green: 0.80, blue: 0.40, alpha: 1),  // green
        33: NSColor(red: 0.95, green: 0.78, blue: 0.22, alpha: 1),  // yellow
        34: NSColor(red: 0.27, green: 0.52, blue: 0.95, alpha: 1),  // blue
        35: NSColor(red: 0.80, green: 0.44, blue: 0.90, alpha: 1),  // magenta
        36: NSColor(red: 0.27, green: 0.84, blue: 0.88, alpha: 1),  // cyan
        37: NSColor(red: 0.83, green: 0.83, blue: 0.83, alpha: 1),  // white
        // Bright variants
        90: NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
        91: NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1),
        92: NSColor(red: 0.55, green: 1.00, blue: 0.55, alpha: 1),
        93: NSColor(red: 1.00, green: 1.00, blue: 0.40, alpha: 1),
        94: NSColor(red: 0.40, green: 0.60, blue: 1.00, alpha: 1),
        95: NSColor(red: 1.00, green: 0.55, blue: 1.00, alpha: 1),
        96: NSColor(red: 0.40, green: 1.00, blue: 1.00, alpha: 1),
        97: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    ]

    // MARK: - Public API

    public init() {}

    /// Appends text to the buffer, parsing ANSI escape codes into attributed colors.
    public func append(_ string: String) {
        let parsed = Self.parseANSI(string)
        let mutable = NSMutableAttributedString(attributedString: text)
        mutable.append(parsed)
        text = mutable
    }

    /// Clears the terminal buffer.
    public func clear() {
        text = NSAttributedString()
    }

    // MARK: - ANSI Parser

    /// Parses a string with ANSI SGR escape sequences into an NSAttributedString.
    ///
    /// Supported codes:
    ///   - ESC[0m          — reset
    ///   - ESC[1m          — bold (slightly brighter text)
    ///   - ESC[30–37m      — standard foreground colors
    ///   - ESC[90–97m      — bright foreground colors
    ///   - ESC[1;31m etc.  — combined bold + color
    ///   - Other codes are stripped silently.
    static func parseANSI(_ string: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Current SGR state
        var currentColor: NSColor = defaultTextColor
        var isBold = false

        // We scan through the string segment-by-segment, splitting on ESC (U+001B).
        var remaining = string[...]

        while !remaining.isEmpty {
            if let escIdx = remaining.firstIndex(of: "\u{1B}") {
                // Append everything before the escape sequence
                let before = remaining[remaining.startIndex..<escIdx]
                if !before.isEmpty {
                    result.append(
                        attributed(String(before), color: currentColor, bold: isBold)
                    )
                }

                // Try to consume an SGR sequence: ESC [ ... m
                let afterEsc = remaining.index(after: escIdx)
                guard afterEsc < remaining.endIndex,
                      remaining[afterEsc] == "[" else {
                    // Not an SGR sequence — just emit the ESC literally and move on
                    result.append(attributed("\u{1B}", color: currentColor, bold: isBold))
                    remaining = remaining[afterEsc...]
                    continue
                }

                let afterBracket = remaining.index(after: afterEsc)
                // Find the closing 'm'
                if let mIdx = remaining[afterBracket...].firstIndex(of: "m") {
                    let params = String(remaining[afterBracket..<mIdx])
                    // Parse semicolon-separated param codes
                    let codes = params.split(separator: ";").compactMap { Int($0) }
                    (currentColor, isBold) = apply(
                        codes: codes.isEmpty ? [0] : codes,
                        currentColor: currentColor,
                        isBold: isBold
                    )
                    remaining = remaining[remaining.index(after: mIdx)...]
                } else {
                    // Malformed escape — emit raw and skip
                    result.append(attributed(String(remaining[escIdx...afterEsc]), color: currentColor, bold: isBold))
                    remaining = remaining[afterBracket...]
                }
            } else {
                // No more escape sequences — append everything
                result.append(attributed(String(remaining), color: currentColor, bold: isBold))
                break
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func apply(
        codes: [Int],
        currentColor: NSColor,
        isBold: Bool
    ) -> (NSColor, Bool) {
        var color = currentColor
        var bold = isBold

        for code in codes {
            switch code {
            case 0:
                color = defaultTextColor
                bold = false
            case 1:
                bold = true
            case 22:
                bold = false
            case 39:
                color = defaultTextColor
            case let c where ansiColors[c] != nil:
                color = ansiColors[c]!
            default:
                break // ignore unsupported codes
            }
        }
        return (color, bold)
    }

    private static func attributed(_ string: String, color: NSColor, bold: Bool) -> NSAttributedString {
        let font: NSFont
        if bold {
            font = NSFont(name: "SF Mono", size: 11).flatMap {
                NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask)
            } ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        } else {
            font = terminalFont
        }

        return NSAttributedString(
            string: string,
            attributes: [
                .foregroundColor: color,
                .font: font,
            ]
        )
    }
}
