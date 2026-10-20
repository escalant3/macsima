// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin

/// CPU time used by Maxima's processes, for the status bar's CPU figure
/// (wxMaxima polls its child's CPU use too). The maxima script runs SBCL
/// in the same process group, so the group's processes are summed.
public enum ProcessCPU {
    /// User plus system time of every live process in `group`; nil when
    /// none can be read.
    public static func time(ofGroup group: pid_t) -> Duration? {
        var pids = [pid_t](repeating: 0, count: 64)
        // The number of pids found (not bytes, unlike proc_listpids).
        let count = proc_listpgrppids(group, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return nil }
        var ticks: UInt64 = 0
        var found = false
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size {
                ticks += info.pti_total_user + info.pti_total_system
                found = true
            }
        }
        guard found else { return nil }
        // Mach time units, not nanoseconds, on Apple silicon.
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return .nanoseconds(Int64(ticks * UInt64(base.numer) / UInt64(base.denom)))
    }

    /// Percent of one core between two samples `elapsed` apart.
    public static func percent(from earlier: Duration, to later: Duration, over elapsed: Duration) -> Double {
        guard elapsed > .zero else { return 0 }
        return max(0, (later - earlier) / elapsed * 100)
    }
}
