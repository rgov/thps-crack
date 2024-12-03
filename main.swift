import Foundation
import Metal

// MARK: - Data Structures

struct Parameters {
    var window_offset: UInt64
    var target_hash_1: UInt32
    var target_hash_2: UInt32
    var max_length: UInt8
}

typealias UInt8x32 = (  // swift sucks at fixed arrays!
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8
)

struct HashResult {
    var found: Bool
    var length: UInt8
    var sequence: UInt8x32
}

// MARK: - Constants

let CHARSET: [Character] = ["S", "X", "C", "T", "L", "D", "R", "U"]
let MAX_WINDOW_SIZE = 65536 * 65536 - 1  // Adjust based on GPU capabilities

// MARK: - Main Program

// Parse command line arguments
guard CommandLine.arguments.count == 4 else {
    print(
        "Usage: hash-search max_length target_hash_1(hex) target_hash_2(hex)"
    )
    exit(1)
}

guard let maxLength = UInt8(CommandLine.arguments[1]),
    let targetHash1 = UInt32(
        CommandLine.arguments[2].replacingOccurrences(of: "0x", with: ""), radix: 16),
    let targetHash2 = UInt32(
        CommandLine.arguments[3].replacingOccurrences(of: "0x", with: ""), radix: 16)
else {
    print("Invalid arguments")
    exit(1)
}

// Set up Metal
guard let device = MTLCopyAllDevices().first else {
    fatalError("Metal is not supported on this device")
}

let queue = device.makeCommandQueue()!

let library = try! device.makeDefaultLibrary(bundle: Bundle.main)

let searchDesc = MTLComputePipelineDescriptor()
searchDesc.computeFunction = library.makeFunction(name: "search_preimage")!
searchDesc.buffers[0].mutability = .immutable  // parameters
searchDesc.buffers[1].mutability = .mutable  // result

// Create buffers
let paramsBuffer = device.makeBuffer(
    length: MemoryLayout<Parameters>.stride,
    options: .storageModeShared
)!

let resultBuffer = device.makeBuffer(
    length: MemoryLayout<HashResult>.offset(of: \HashResult.sequence)! + 32,
    options: .storageModeShared
)!

// Helper function to convert sequence to string
func sequenceToString(_ sequence: UInt8x32, length: Int) -> String {
    let values = Mirror(reflecting: sequence).children.map { $0.value as! UInt8 }
    return values[..<length].map { CHARSET[Int($0)] }.map(String.init).joined()
}

// Search function
func search() -> Bool {
    print("Searching sequences up to length \(maxLength)...")
    print()

    // Calculate search space based on maximum length
    let searchSpace = UInt64(1 << (3 * maxLength))  // 8^maxLength
    var windowOffset: UInt64 = 0

    let resultPtr = resultBuffer.contents().assumingMemoryBound(to: HashResult.self)
    let paramsPtr = paramsBuffer.contents().assumingMemoryBound(to: Parameters.self)

    while windowOffset < searchSpace {
        let windowSize = min(MAX_WINDOW_SIZE, Int(searchSpace - windowOffset))

        // Update parameters
        paramsPtr.pointee = Parameters(
            window_offset: windowOffset,
            target_hash_1: targetHash1,
            target_hash_2: targetHash2,
            max_length: maxLength
        )

        // Create and execute command buffer
        let cmdBuffer = queue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(
            try! device.makeComputePipelineState(
                descriptor: searchDesc,
                options: [],
                reflection: nil
            ))

        encoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        encoder.setBuffer(resultBuffer, offset: 0, index: 1)

        encoder.dispatchThreads(
            MTLSizeMake(windowSize, 1, 1),
            threadsPerThreadgroup: MTLSizeMake(1, 1, 1)
        )

        encoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // Check result
        if resultPtr.pointee.found {
            print("\u{1B}[1A\u{1B}[2K\rProgress: 100.00%")

            let sequence = sequenceToString(
                resultPtr.pointee.sequence,
                length: Int(resultPtr.pointee.length))
            print("Found solution: \(sequence)")

            // Verify the hash
            print(String(format: "Target hashes: 0x%08X 0x%08X", targetHash1, targetHash2))
            return true
        }

        // Update progress
        let progress = Double(windowOffset + UInt64(windowSize)) / Double(searchSpace) * 100
        print("\u{1B}[1A\u{1B}[2K\rProgress: \(String(format: "%.2f", progress))%")

        windowOffset += UInt64(windowSize)
    }

    return false
}

// Execute search
if !search() {
    print("Exhausted :(")
    exit(1)
}
