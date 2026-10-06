import DiskCleanerCore

func decimalUnits() {
    Expect.equal(ByteFormat.string(from: 0), "0 B")
    Expect.equal(ByteFormat.string(from: 999), "999 B")
    Expect.equal(ByteFormat.string(from: 1_000), "1 KB")
    Expect.equal(ByteFormat.string(from: 1_200), "1.2 KB")
    Expect.equal(ByteFormat.string(from: 1_600_000_000), "1.6 GB")
    Expect.equal(ByteFormat.string(from: 22_000_000_000), "22 GB")
}

func percentOfScannedTotal() {
    Expect.equal(ByteFormat.percent(part: 50, total: 0), 0)
    Expect.equal(ByteFormat.percent(part: 0, total: 200), 0)
    Expect.equal(ByteFormat.percent(part: 50, total: 200), 25)
    Expect.equal(ByteFormat.percent(part: 1, total: 3), 33)
    Expect.equal(ByteFormat.percent(part: 2, total: 3), 67)
}
