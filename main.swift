import Foundation
import Metal

// MARK: - Data Structures

struct Parameters {
    var window_offset: UInt64
    var target_hash_1: UInt32
    var target_hash_2: UInt32
    var sequence_length: UInt8
    var repetitions: UInt8
}

typealias UInt8x32 = (  // swift sucks at fixed arrays!
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8
)

struct HashResult {
    var found: Bool
    var sequence: UInt8x32
}

// MARK: - Constants

let CHARSET: [Character] = ["S", "X", "C", "T", "L", "D", "R", "U"]
let MAX_WINDOW_SIZE = 65536 * 65536 - 1  // Adjust based on GPU capabilities

// MARK: - Main Program

// Parse command line arguments
guard CommandLine.arguments.count == 7 else {
    print(
        "Usage: hash-search min_length max_length min_repetitions max_repetitions target_hash_1(hex) target_hash_2(hex)"
    )
    exit(1)
}

guard let minLength = UInt8(CommandLine.arguments[1]),
    let maxLength = UInt8(CommandLine.arguments[2]),
    let minRepetitions = UInt8(CommandLine.arguments[3]),
    let maxRepetitions = UInt8(CommandLine.arguments[4]),
    let targetHash1 = UInt32(
        CommandLine.arguments[5].replacingOccurrences(of: "0x", with: ""), radix: 16),
    let targetHash2 = UInt32(
        CommandLine.arguments[6].replacingOccurrences(of: "0x", with: ""), radix: 16)
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
func sequenceToString(_ sequence: UInt8x32, length: Int, repetitions: Int) -> String {
    let values = Mirror(reflecting: sequence).children.map { $0.value as! UInt8 }
    let singleSequence = values[..<length].map { CHARSET[Int($0)] }.map(String.init).joined()
    return String(repeating: singleSequence, count: repetitions)
}

// Main search loop
func searchLength(_ length: UInt8, repetitions: UInt8) -> Bool {
    print("Searching sequences of length \(length) with \(repetitions) repetitions...")
    print()

    let searchSpace = UInt64(1 << (3 * length))
    var windowOffset: UInt64 = 0

    while windowOffset < searchSpace {
        let windowSize = min(MAX_WINDOW_SIZE, Int(searchSpace - windowOffset))

        // Clear previous result
        let resultPtr = resultBuffer.contents().assumingMemoryBound(to: HashResult.self)
        resultPtr.pointee.found = false

        // Update parameters
        let paramsPtr = paramsBuffer.contents().assumingMemoryBound(to: Parameters.self)
        paramsPtr.pointee = Parameters(
            window_offset: windowOffset,
            target_hash_1: targetHash1,
            target_hash_2: targetHash2,
            sequence_length: length,
            repetitions: repetitions
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
                resultPtr.pointee.sequence, length: Int(length), repetitions: Int(repetitions))
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

// Execute search for each combination of length and repetitions
for length in minLength...maxLength {
    for repetitions in minRepetitions...maxRepetitions {
        if searchLength(length, repetitions: repetitions) {
            exit(0)
        }
    }
}

print("Exhausted :(")
exit(1)
