import Foundation

// MARK: - C 函数声明（链 libtdjson 时这些 symbol 自动可解析）

@_silgen_name("td_create_client_id")
func td_create_client_id() -> Int32

@_silgen_name("td_send")
func td_send(_ client_id: Int32, _ request: UnsafePointer<CChar>)

@_silgen_name("td_receive")
func td_receive(_ timeout: Double) -> UnsafePointer<CChar>?

@_silgen_name("td_execute")
func td_execute(_ request: UnsafePointer<CChar>) -> UnsafePointer<CChar>?
