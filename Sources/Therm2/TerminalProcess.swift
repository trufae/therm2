import Darwin

struct TerminalProcess {
    private let info: proc_bsdinfo

    private var pid: pid_t { pid_t(info.pbi_pid) }
    var parentPID: pid_t { pid_t(info.pbi_ppid) }
    var hasExecuted: Bool { info.pbi_flags & UInt32(PROC_FLAG_EXEC) != 0 }

    init?(pid: pid_t) {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != SZOMB, info.pbi_flags & UInt32(PROC_FLAG_INEXIT) == 0 else { return nil }
        self.info = info
    }

    var executablePath: String? {
        // libproc's largest path buffer is PROC_PIDPATHINFO_MAXSIZE.
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: path.prefix(Int(length)), as: UTF8.self)
    }

    var children: [TerminalProcess] {
        var pids = [pid_t](repeating: 0, count: 16)
        while true {
            let count = pids.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
            if count < pids.count {
                let children = pids.prefix(max(0, Int(count))).compactMap { childPID -> TerminalProcess? in
                    guard let child = TerminalProcess(pid: childPID), child.parentPID == pid else { return nil }
                    return child
                }
                // The parent can exit while libproc is enumerating its PIDs.
                return currentProcess == nil ? [] : children
            }
            pids = [pid_t](repeating: 0, count: pids.count * 2)
        }
    }

    func terminateDescendants() {
        // Take the whole snapshot before signaling parents, which can orphan their children.
        var descendants = children
        var index = 0
        while index < descendants.count {
            let child = descendants[index]
            descendants.append(contentsOf: child.children)
            index += 1
        }
        for child in descendants.reversed() {
            guard let current = child.currentProcess else { continue }
            if kill(child.pid, SIGTERM) == 0, current.info.pbi_status == SSTOP {
                kill(child.pid, SIGCONT)
            }
        }
    }

    private var currentProcess: TerminalProcess? {
        guard let current = TerminalProcess(pid: pid),
              current.info.pbi_start_tvsec == info.pbi_start_tvsec,
              current.info.pbi_start_tvusec == info.pbi_start_tvusec else { return nil }
        return current
    }
}
