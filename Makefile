FRAMEWORK      = -framework Network -framework AppKit
BUILD_FLAGS    = -Wall -O2 -fvisibility=hidden -mmacosx-version-min=10.14 -fno-objc-arc -arch x86_64 -arch arm64
BUILD_PATH     = ./bin
BINS           = $(BUILD_PATH)/sys_appearance
SRC            = ./src/app.m

.PHONY: all clean

all: clean $(BINS)

clean:
	rm -rf $(BUILD_PATH)

$(BUILD_PATH)/sys_appearance: $(SRC)
	mkdir -p $(BUILD_PATH)
	xcrun clang $^ $(BUILD_FLAGS) $(FRAMEWORK) -o $@
