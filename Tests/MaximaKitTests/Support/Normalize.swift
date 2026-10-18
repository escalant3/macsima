// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Replaces the machine-specific text the fixtures README lists (PIDs, ports,
/// temp-file names, Lisp addresses, home folders) with fixed placeholders, so
/// tests can compare the rest literally.
enum Normalize {
    private static let rules: [(pattern: String, replacement: String)] = [
        (#"pid=\d+"#, "pid=<PID>"),
        (#"/var/folders/[^\s<"]+"#, "<TMPFILE>"),
        (#"maxout_\d+_[\w.]+"#, "<MAXOUT>"),
        (#"#x[0-9A-Fa-f]+"#, "#x<ADDR>"),
        (#"/Users/[^/\s<"]+"#, "<HOME>"),
        (#"port \d+"#, "port <PORT>"),
        (#""127\.0\.0\.1" \d+"#, "\"127.0.0.1\" <PORT>"),
    ]

    static func text(_ s: String) -> String {
        var out = s
        for rule in rules { out.replace(try! Regex(rule.pattern), with: rule.replacement) }
        return out
    }
}
