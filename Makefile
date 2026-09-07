# 1541HUD repository build wrapper
#
# The inherited OneROM build tree lives under OneROM/ so the repository root
# remains focused on 1541HUD.  Build targets are delegated to the retained
# OneROM Makefile.

.PHONY: all clean

all:
	$(MAKE) -C OneROM

clean:
	$(MAKE) -C OneROM clean

%:
	$(MAKE) -C OneROM $@
