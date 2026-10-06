import Foundation

package enum ByteFormat {
    /// Decimal units, matching the size the spec shows (1 KB = 1,000 bytes).
    package static func string(from bytes: Int64) -> String {
        var amount = Double(max(bytes, 0))
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var index = 0
        while amount >= 1_000, index < units.count - 1 {
            amount /= 1_000
            index += 1
        }
        if index == 0 {
            return "\(Int(amount)) B"
        }
        return "\(trim(amount)) \(units[index])"
    }

    /// Share of the scanned total. A zero total is 0%.
    package static func percent(part: Int64, total: Int64) -> Int {
        guard total > 0, part > 0 else { return 0 }
        return Int((Double(part) / Double(total) * 100).rounded())
    }

    private static func trim(_ amount: Double) -> String {
        let text = String(format: "%.1f", amount)
        if text.hasSuffix(".0") {
            return String(text.dropLast(2))
        }
        return text
    }
}
