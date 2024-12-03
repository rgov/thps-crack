#include <metal_stdlib>

using namespace metal;

static constant uint32_t x[8] = {
    0x03185332, 0xB87610DB, 0xDEADBEEF, 0x31415926,
    0x93FE1682, 0x776643D1, 0xAB432901, 0x01234567
};

static constant uint32_t y[8] = {
    0x80FE4187, 0xDE098401, 0xFE3010F3, 0x7720DE42,
    0x92551072, 0x0901D3E8, 0x88D3A109, 0x34859F3A
};

struct Parameters {
    uint64_t window_offset;    // Starting offset for this window in the search space
    uint32_t target_hash_1;    // First target hash value
    uint32_t target_hash_2;    // Second target hash value
    uint8_t sequence_length;  // Length of sequences to generate
    uint8_t  repetitions;      // Number of times to run the hash function
};

// Convert a position in the search space into a sequence of elements (0-7)
void index_to_sequence(uint64_t index, thread uint8_t* sequence, uint32_t length) {
    for (uint32_t i = 0; i < length; i++) {
        sequence[i] = uint8_t(index % 8);
        index /= 8;
    }
}

struct HashPair {
    uint32_t hash1;
    uint32_t hash2;
};

// Hash function that produces two different hash values
HashPair hash_sequence(thread const uint8_t* sequence, uint8_t length, uint8_t repetitions) {
    HashPair result = {0, 0};

    // Outer loop for repetitions
    for (uint32_t rep = 0; rep < repetitions; rep++) {
        // Inner loop over sequence elements
        for (uint32_t i = 0; i < length; i++) {
            uint32_t j = sequence[i];

            uint32_t temp1 = result.hash1 ^ x[j];
            result.hash1 = ((temp1 << 1) ^ (temp1 >> 31)) * 0x209;

            uint32_t temp2 = result.hash2 ^ y[j] ^ (result.hash1 >> 8);
            result.hash2 = (temp2 << 1) ^ ((result.hash2 ^ y[j]) >> 31);
        }
    }

    return result;
}

struct HashResult {
    bool found;            // Whether a matching sequence was found
    uint8_t sequence[32];  // Sequence that produces the target hashes
};

kernel void search_preimage(
    device const Parameters& params [[buffer(0)]],
    device HashResult& result [[buffer(1)]],
    uint thread_position_in_grid [[thread_position_in_grid]],
    uint threads_per_grid [[threads_per_grid]]
) {
    // Calculate the global index for this thread
    uint64_t global_index = params.window_offset + thread_position_in_grid;

    // Generate sequence for this thread
    uint8_t sequence[32];  // Local stack allocation for sequence
    index_to_sequence(global_index, sequence, params.sequence_length);

    // Calculate both hashes with the specified number of repetitions
    HashPair hashes = hash_sequence(sequence, params.sequence_length, params.repetitions);

    // If we found a sequence that produces both target hashes
    if (hashes.hash1 == params.target_hash_1 && hashes.hash2 == params.target_hash_2) {
        bool expected = false;
        if (atomic_compare_exchange_weak_explicit(
            (volatile device atomic_bool*)&result.found,
            &expected,
            true,
            memory_order_relaxed,
            memory_order_relaxed
        )) {
            // Store the sequence that produced our target hashes
            for (uint32_t i = 0; i < params.sequence_length; i++) {
                result.sequence[i] = sequence[i];
            }
        }
    }
}
