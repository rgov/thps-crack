'''
Solver for the hash function used by Tony Hawk's Pro Skater 2 cheat codes using
the Z3 theorem prover.

Based on this blog post, all credit to the author behind the post.
https://32bits.substack.com/p/under-the-microscope-tony-hawks-pro

Largely written by ChatGPT o1-preview.
'''

from z3 import *  # pip install z3-solver

N = 9  # Length of the button sequence
R = 1  # Number of repetitions
assert N % R == 0

s = Solver()

# Use an array to represent the hash values over successive iterations
HASH_1 = [BitVec('HASH_1_%d' % i, 32) for i in range(N + 1)]
HASH_2 = [BitVec('HASH_2_%d' % i, 32) for i in range(N + 1)]

# Initial hash values are zero
s.add(HASH_1[0] == 0)
s.add(HASH_2[0] == 0)

# Desired final hash values
s.add(HASH_1[N] == 0x1eca8e89)
s.add(HASH_2[N] == 0xad2dc1d6)

# Variables representing the sequence of button presses
buttons = [Int('button_%d' % i) for i in range(N)]
for btn in buttons:
    s.add(btn >= 0, btn <= 7)  # Button indices from 0 to 7

# Enforce repetition of the sequence
for i in range(N//R, N):
    s.add(buttons[i] == buttons[i % (N//R)])


# Button mappings to x and y values as in the post
button_map = {
    'SQUARE':   (0x03185332, 0x80FE4187),
    'X':        (0xB87610DB, 0xDE098401),
    'CIRCLE':   (0xDEADBEEF, 0xFE3010F3),
    'TRIANGLE': (0x31415926, 0x7720DE42),
    'LEFT':     (0x93FE1682, 0x92551072),
    'DOWN':     (0x776643D1, 0x0901D3E8),
    'RIGHT':    (0xAB432901, 0x88D3A109),
    'UP':       (0x01234567, 0x34859F3A),
}

# Update hash values based on button presses
for i in range(N):
    # Build a big nested If()
    for j, (x_const, y_const) in enumerate(button_map.values()):
        if j == 0:
            x = BitVecVal(x_const, 32)
            y = BitVecVal(y_const, 32)
        else:
            x = If(buttons[i] == j, BitVecVal(x_const, 32), x)
            y = If(buttons[i] == j, BitVecVal(y_const, 32), y)

    temp1 = HASH_1[i] ^ x
    temp2 = (temp1 << 1) ^ LShR(temp1, 0x1F)
    s.add(HASH_1[i + 1] == temp2 * 0x209)

    temp3 = HASH_2[i] ^ y ^ LShR(HASH_1[i + 1], 8)
    temp4 = temp3 << 1
    temp5 = LShR(HASH_2[i] ^ y, 0x1F)
    s.add(HASH_2[i + 1] == temp4 ^ temp5)


# Solve for the button sequence
if s.check() == sat:
    m = s.model()
    button_names = list(button_map.keys())
    print('Solution:',
          ', '.join(button_names[m.evaluate(b).as_long()] for b in buttons))
    print('HASH 1: ',
          ', '.join(hex(m.evaluate(h).as_long()) for h in HASH_1))
    print('HASH 2: ',
          ', '.join(hex(m.evaluate(h).as_long()) for h in HASH_2))
else:
    print('No solution found.')
