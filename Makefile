OUTPUT = thpscrack

SWIFT_FILES = $(wildcard *.swift)
METAL_FILES = $(wildcard *.metal)
METAL_IR_FILES = $(METAL_FILES:.metal=.ir)
METAL_LIBRARY = default.metallib

# Xcode SDK
SDK = macosx

# Metal and Swift compiler commands
METALC = xcrun -sdk $(SDK) metal
METALLIB = xcrun -sdk $(SDK) metallib
SWIFTC = swiftc

# Build targets
all: $(OUTPUT)

$(OUTPUT): $(METAL_LIBRARY) $(SWIFT_FILES)
	$(SWIFTC) -g -O -framework Metal -o $(OUTPUT) $(SWIFT_FILES)

$(METAL_LIBRARY): $(METAL_IR_FILES)
	$(METALLIB) -o $(METAL_LIBRARY) $(METAL_IR_FILES)

%.ir: %.metal
	$(METALC) -c $< -o $@

clean:
	rm -f $(METAL_IR_FILES) $(METAL_LIBRARY) $(OUTPUT)

.PHONY: all clean
