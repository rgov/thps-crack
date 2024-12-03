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
    uint8_t max_length;        // Maximum sequence length to try
};

struct HashResult {
    bool found;            // Whether a matching sequence was found
    uint8_t length;        // Length of successful sequence
    uint8_t sequence[32];  // Sequence that produces the target hashes
};

// Convert a position in the search space into a sequence of elements (0-7)
void index_to_sequence(uint64_t index, thread uint8_t* sequence, uint8_t length) {
    for (uint8_t i = 0; i < length; i++) {
        sequence[i] = uint8_t(index % 8);
        index /= 8;
    }
}

bool check_hash2(uint32_t target_hash_2,
                 thread const uint8_t* sequence,
                 uint8_t length) {

    // Some cheats only use a single hash
    if (target_hash_2 == 0)
        return true;

    uint32_t hash_1 = 0;
    uint32_t hash_2 = 0;

    for (uint8_t i = 0; i < length; i++) {
        uint32_t temp1 = hash_1 ^ x[sequence[i]];
        hash_1 = ((temp1 << 1) ^ (temp1 >> 31)) * 0x209;
        uint32_t temp2 = hash_2 ^ y[sequence[i]] ^ (hash_1 >> 8);
        hash_2 = (temp2 << 1) ^ ((hash_2 ^ y[sequence[i]]) >> 31);
    }

    return hash_2 == target_hash_2;
}

// Returns the length of the matching subsequence, or 0 if no match
uint8_t check_hash(uint32_t target_hash_1, uint32_t target_hash_2,
                   thread const uint8_t* sequence,
                   uint8_t length) {

    uint32_t hash_1 = 0;

    for (uint8_t i = 0; i < length; i++) {
        uint32_t temp1 = hash_1 ^ x[sequence[i]];
        hash_1 = ((temp1 << 1) ^ (temp1 >> 31)) * 0x209;

        if (hash_1 != target_hash_1)
            continue;

        // We have a collision with target_hash_1, do another loop to
        // evaluate target_hash_2.
        if (check_hash2(target_hash_2, sequence, i + 1)) {
            return i + 1;  // Found it!
        }
    }

    return 0;  // no match
}

kernel void search_preimage(
    device const Parameters& params [[buffer(0)]],
    device HashResult& result [[buffer(1)]],
    uint thread_position_in_grid [[thread_position_in_grid]]
) {
    // Calculate the global index for this thread
    uint64_t global_index = params.window_offset + thread_position_in_grid;

    // Generate sequence for this thread
    uint8_t sequence[32];  // Local stack allocation for sequence
    index_to_sequence(global_index, sequence, params.max_length);

    uint8_t out_length = check_hash(
        params.target_hash_1,
        params.target_hash_2,
        sequence,
        params.max_length
    );

    if (out_length > 0) {
        bool expected = false;
        if (atomic_compare_exchange_weak_explicit(
            (volatile device atomic_bool*)&result.found,
            &expected,
            true,
            memory_order_relaxed,
            memory_order_relaxed
        )) {
            // Return the successful sequence
            for (uint32_t i = 0; i < out_length; i++) {
                result.sequence[i] = sequence[i];
            }
            result.length = out_length;
        }
    }
}
