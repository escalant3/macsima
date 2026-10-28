// SPDX-License-Identifier: GPL-2.0-or-later
//
// The explanations are ported from wxMaxima's TextCell::UpdateToolTip()
// (src/cells/TextCell.cpp, commit 13e4aee), which wxMaxima 26.09 shows as a
// tooltip on a message it marks in yellow:
//
//  Copyright (C) 2004-2015 Andrej Vodopivec <andrej.vodopivec@gmail.com>
//            (C) 2014-2018 Gunter Königsmann <wxMaxima@physikbuch.de>
//            (C) 2020      Kuba Ober <kuba@bertec.com>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// What a Maxima error or warning most likely means, for the messages
/// wxMaxima explains. Only the text-message part of wxMaxima's table: the
/// rest explains symbols inside rendered math (`pnz`, `%r1`, ...).
public enum MessageExplanations {
    private enum Test {
        case prefix(String), contains(String)
        case all([Test])
        case any([Test])

        func matches(_ text: String) -> Bool {
            switch self {
            case .prefix(let p): text.hasPrefix(p)
            case .contains(let c): text.contains(c)
            case .all(let tests): tests.allSatisfy { $0.matches(text) }
            case .any(let tests): tests.contains { $0.matches(text) }
            }
        }
    }

    /// In wxMaxima's order: the first match wins.
    private static let table: [(Test, String)] = [
        (.any([.contains("LINE SEARCH FAILED. SEE"), .contains("DOCUMENTATION OF ROUTINE MCSRCH"),
               .contains("ERROR RETURN OF LINE SEARCH:"), .contains("POSSIBLE CAUSES: FUNCTION OR GRADIENT ARE INCORRECT")]),
         String(localized: "This message can appear when trying to numerically find an optimum. In this case it might indicate that a starting point lies in a local optimum that fits the data best if one parameter is increased to infinity or decreased to -infinity. It also can indicate that an attempt was made to fit data to an equation that actually matches the data best if one parameter is set to +/- infinity.")),
        (.all([.prefix("incorrect syntax"), .contains("is not an infix operator")]),
         String(localized: "A command or number wasn't preceded by a \":\", a \"$\", a \";\" or a \",\".\nMost probable cause: A missing comma between two list items.")),
        (.all([.prefix("incorrect syntax"), .contains("Found LOGICAL expression where ALGEBRAIC expression expected")]),
         String(localized: "Most probable cause: A dot instead a comma between two list items containing assignments.")),
        (.all([.prefix("incorrect syntax"), .contains("is not a prefix operator")]),
         String(localized: "Most probable cause: Two commas or similar separators in a row.")),
        (.contains("Illegal use of delimiter"),
         String(localized: "Most probable cause: an operator was directly followed by a closing parenthesis.")),
        (.prefix("find_root: function has same sign at endpoints: "),
         String(localized: "Maxima tried to find out where between two points a curve crosses the zero line. Since the curve is on the same side of the zero line in both points its algorithms fails here. Set find_root_error to false if you want it to return false instead of an error.")),
        (.prefix("part: fell off the end."),
         String(localized: "part() or the [] operator was used in order to extract the nth element of something that was less than n elements long.")),
        (.prefix("rest: fell off the end."),
         String(localized: "rest() tried to drop more entries from a list than the list was long.")),
        (.prefix("assignment: cannot assign to"),
         String(localized: "The value of few special variables is assigned by Maxima and cannot be changed by the user. Also a few constructs aren't variable names and therefore cannot be written to.")),
        (.prefix("rat: replaced "),
         String(localized: "Normally computers use floating-point numbers that can be handled incredibly fast while being accurate to dozens of digits. They will, though, introduce a small error into some common numbers. For example 0.1 is represented as 3602879701896397/36028797018963968.\nAs mathematics is based on the fact that numbers that are exactly equal cancel each other out small errors can quickly add up to big errors (see Wilkinson's Polynomials or Rump's Polynomials). Some maxima commands therefore use rat() in order to automatically convert floats to exact numbers (like 1/10 or sqrt(2)/2) where floating-point errors might add up.\n\nThis error message doesn't occur if exact numbers (1/10 instead of 0.1) are used.\nThe info that numbers have automatically been converted can be suppressed by setting ratprint to false.")),
        (.prefix("desolve: can't handle this case."),
         String(localized: "The list of time-dependent variables to solve to doesn't match the time-dependent variables the list of dgls contains.")),
        (.prefix("expt: undefined: 0 to a negative exponent."), String(localized: "Division by 0.")),
        (.prefix("Refusing to factor polynomial"),
         String(localized: "This warning can be deactivated by setting factor_max_degree_print_warning to false.")),
        (.prefix("incorrect syntax: parser: incomplete number; missing exponent?"),
         String(localized: "Might also indicate a missing multiplication sign (\"*\").")),
        (.contains("arithmetic error DIVISION-BY-ZERO signalled"),
         String(localized: "Besides a division by 0 the reason for this error message can be a calculation that returns +/-infinity.")),
        (.contains("isn't in the domain of"),
         String(localized: "Most probable cause: A function was called with a parameter that causes it to return infinity and/or -infinity.")),
        (.prefix("Only symbols can be bound"),
         String(localized: "This error message is most probably caused by a try to assign a value to a number instead of a variable name.\nOne probable cause is using a variable that already has a numeric value as a loop counter.")),
        (.prefix("append: operators of arguments must all be the same."),
         String(localized: "Most probably it was attempted to append something to a list that isn't a list.\nEnclosing the new element for the list in brackets ([]) converts it to a list and makes it appendable.")),
        (.contains("matrix: all rows must be the same length"),
         String(localized: "Might be caused by reading an csv file with an empty last line:\nTechnically that line can be described as having the length 0 which differs from the other lines of this file.")),
        (.contains("expected a polynomial"),
         String(localized: "If the thing maxima complains about actually looks like a polynomial you can try running it through ratdisrep() in order to fix that problem.")),
        (.contains("Control stack exhausted"),
         String(localized: "Often caused by recursive function calls. Some lisps allow increasing the control stack size using command-line arguments.")),
        (.contains(": invalid index"),
         String(localized: "The [] or the part() command tried to access a list or matrix element that doesn't exist.")),
        (.prefix("apply: subscript must be an integer; found:"),
         String(localized: "the [] operator tried to extract an element of a list, a matrix, an equation or an array. But instead of an integer number something was used whose numerical value is unknown or not an integer.\nFloating-point numbers are bound to contain small rounding errors and therefore in most cases don't work as an array index thatneeds to be an exact integer number.")),
    ]

    /// The explanation for a message, if wxMaxima has one. A message of
    /// several lines is matched line by line, as wxMaxima's text cells hold
    /// one line each; the first line with an explanation counts.
    public static func explanation(for message: String) -> String? {
        for line in message.split(whereSeparator: \.isNewline).map(String.init) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let hit = table.first(where: { $0.0.matches(text) }) { return hit.1 }
            // wxMaxima's ": improper argument: " case looks at the function
            // name before it, which Maxima prints in the same line here.
            if let range = text.range(of: ": improper argument: ") {
                switch text[..<range.lowerBound] {
                case "at": return String(localized: "The second argument of at() isn't an equation or a list of equations. Most probably it was lacking an \"=\".")
                case "subst": return String(localized: "The first argument of subst() isn't an equation or a list of equations. Most probably it was lacking an \"=\".")
                default: return String(localized: "The argument of a function was of the wrong type. Most probably an equation was expected but was lacking an \"=\".")
                }
            }
        }
        return nil
    }
}
