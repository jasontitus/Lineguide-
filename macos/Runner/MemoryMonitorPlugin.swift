import FlutterMacOS
import Darwin

/// macOS native plugin that reports process memory usage.
class MemoryMonitorPlugin: NSObject {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.lineguide/memory_monitor",
            binaryMessenger: messenger
        )
        super.init()
        channel.setMethodCallHandler(handle)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getMemoryUsage":
            let physicalMB = getPhysicalFootprint()
            let totalMB = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024)
            // macOS doesn't have os_proc_available_memory; estimate from total - used
            let availableMB = totalMB - physicalMB

            result([
                "physicalFootprintMB": physicalMB,
                "availableMemoryMB": availableMB,
                "totalPhysicalMemoryMB": totalMB,
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getPhysicalFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Int(info.phys_footprint) / 1024 / 1024
        }
        return 0
    }
}
