#include <stdint.h>
#include <stdio.h>

#define TARGET_HASH_1 0x1ECA8E89
#define TARGET_HASH_2 0xAD2DC1D6

#define MAX_LENGTH 9
#define MIN_LENGTH 9

#define MAX_REPEAT 1


const uint32_t x[8] = {
    0x03185332, 0xB87610DB, 0xDEADBEEF, 0x31415926,
    0x93FE1682, 0x776643D1, 0xAB432901, 0x01234567
};
const uint32_t y[8] = {
    0x80FE4187, 0xDE098401, 0xFE3010F3, 0x7720DE42,
    0x92551072, 0x0901D3E8, 0x88D3A109, 0x34859F3A
};

const char button_letters[8] = {'S', 'X', 'C', 'T', 'L', 'D', 'R', 'U'};


int main() {
    uint8_t sequence[MAX_LENGTH] = { 0 };

    for (int len = MIN_LENGTH; len <= MAX_LENGTH; len ++) {
        printf("Trying length %d\n", len);
        while (1) {
            uint32_t HASH_1 = 0, HASH_2 = 0;

            for (int repeat = 1; repeat <= MAX_REPEAT; repeat ++) {
                uint32_t saved_HASH_1 = HASH_1;

                // Feed in the combination (again)
                for (int i = 0; i < len; i ++) {
                    uint32_t temp1 = HASH_1 ^ x[sequence[i]];
                    HASH_1 = ((temp1 << 1) ^ (temp1 >> 31)) * 0x209;
                }

                // Optimization: bail early
                if (HASH_1 != TARGET_HASH_1)
                    continue;

                // Compute HASH_2 this time
                HASH_1 = saved_HASH_1;
                for (int i = 0; i < len; i ++) {
                    uint32_t temp1 = HASH_1 ^ x[sequence[i]];
                    HASH_1 = ((temp1 << 1) ^ (temp1 >> 31)) * 0x209;
                    uint32_t temp2 = HASH_2 ^ y[sequence[i]] ^ (HASH_1 >> 8);
                    HASH_2 = (temp2 << 1) ^ ((HASH_2 ^ y[sequence[i]]) >> 31);
                }

                // Check for solution now
                if (HASH_2 == TARGET_HASH_2) {
                    printf("Found solution! ");
                    for (int j = 0; j < repeat; j ++) {
                        for (int i = 0; i < len; i++) {
                            printf("%c", button_letters[sequence[i]]);
                        }
                    }
                    printf("\n");
                    return 0;
                }
            }

            // Increment the combination
            int i;
            for (i = 0; i < len; i ++) {
                sequence[i] ++;
                if (sequence[i] == 8)
                    sequence[i] = 0;
                else
                    break;
            }
            if (i == len)
                break;
        }
    }

    printf("Exhausted.\n");
    return 1;
}
