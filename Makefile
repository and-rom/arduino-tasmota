.DEFAULT_GOAL := deploy-sketch

.PHONY:  download extract dirs board repo libs src tune tool prefs config install-ide deploy-sketch run bins scp ota-server clean
#.SILENT:

UNAME_P := $(shell uname -p)

arduino*.tar.xz:
	$(info 1 Downloading Arduino IDE)
	$(eval OS := $(shell uname -s | tr '[:upper:]' '[:lower:]'))
ifeq ($(UNAME_P),x86_64)
	$(eval ARCH := 64)
endif
ifneq ($(filter %86,$(UNAME_P)),)
	$(eval ARCH := 32)
endif
ifneq ($(filter arm%,$(UNAME_P)),)
	$(eval ARCH := arm)
endif
	$(eval PLATFORM := $(OS)$(ARCH))
	$(eval FILENAME := $(shell wget -qO - "https://www.arduino.cc/en/Main/Software" | grep "download_handler.*$(PLATFORM)" | grep -v beta | sed -ne 's/^.*download_handler.php?f=\/\([^"]*\)".*$$/\1/p'))
	wget "https://downloads.arduino.cc/$(FILENAME)" -q --show-progress

download: arduino*.tar.xz

arduino:
	$(info 2 Extracting Arduino IDE)
	tar xJf $(wildcard *.tar.xz) -C ./ --strip=1

extract: download arduino

portable:
	$(info 3 Making portable directory)
	mkdir -p portable/sketchbook

build:
	$(info 3 Making build directory)
	mkdir -p build

dirs: portable build

portable/packages/esp8266:
	$(info 4 Installing boards)
	./arduino --pref "boardsmanager.additional.urls=http://arduino.esp8266.com/stable/package_esp8266com_index.json" --save-prefs
	./arduino --install-boards esp8266:esp8266

board: extract dirs portable/packages/esp8266

Sonoff-Tasmota:
	$(info 5 Cloning repo)
	git clone git@github.com:arendst/Sonoff-Tasmota.git

repo: Sonoff-Tasmota

portable/sketchbook/libraries.orig:
	$(info 6 Adding libraries)
	mv portable/sketchbook/libraries portable/sketchbook/libraries.orig
	ln -s ../../Sonoff-Tasmota/lib portable/sketchbook/libraries

libs: portable/sketchbook/libraries.orig dirs repo 

portable/sketchbook/sonoff:
	$(info 7 Adding source code)
	ln -s ../../Sonoff-Tasmota/sonoff portable/sketchbook/sonoff

src: repo dirs libs portable/sketchbook/sonoff

portable/packages/esp8266/hardware/esp8266/2.4.2/boards.txt.orig:
	$(info 8.1 Tuning board)
	mv portable/packages/esp8266/hardware/esp8266/2.4.2/boards.txt portable/packages/esp8266/hardware/esp8266/2.4.2/boards.txt.orig
	ln -s "../../../../../../Sonoff-Tasmota/arduino/version 2.4.2/boards.txt" "portable/packages/esp8266/hardware/esp8266/2.4.2/boards.txt"

portable/packages/esp8266/hardware/esp8266/2.4.2/platform.txt.orig:
	$(info 8.2 Tuning board)
	mv portable/packages/esp8266/hardware/esp8266/2.4.2/platform.txt portable/packages/esp8266/hardware/esp8266/2.4.2/platform.txt.orig
	ln -s "../../../../../../Sonoff-Tasmota/arduino/version 2.4.2/platform.txt" "portable/packages/esp8266/hardware/esp8266/2.4.2/platform.txt"

tune: portable/packages/esp8266/hardware/esp8266/2.4.2/boards.txt.orig \
	portable/packages/esp8266/hardware/esp8266/2.4.2/platform.txt.orig \
	board src

portable/packages/esp8266/hardware/esp8266/2.4.2/tools/espupload.py:
	$(info 9 Adding upload tool)
	ln -s "../../../../../../../Sonoff-Tasmota/arduino/espupload.py" "portable/packages/esp8266/hardware/esp8266/2.4.2/tools/espupload.py"

tool: board src portable/packages/esp8266/hardware/esp8266/2.4.2/tools/espupload.py

portable/preferences.txt.orig:
	$(info 10 Setting board type, build parameters and IDE preferences)
	cp portable/preferences.txt portable/preferences.txt.orig
	./arduino --board  "esp8266:esp8266:generic:\
                    CpuFrequency=80,\
                    CrystalFreq=26,\
                    Debug=Disabled,\
                    DebugLevel=None____,\
                    FlashErase=none,\
                    FlashFreq=40,\
                    FlashMode=dout,\
                    FlashSize=1M0,\
                    LwIPVariant=v2mss1460,\
                    ResetMethod=nodemcu,\
                    UploadSpeed=57600,\
                    UploadTool=esptool,\
                    VTable=flash,\
                    led=2" \
              --save-prefs
	./arduino --pref "editor.linenumbers=true" --save-prefs
	./arduino --pref "update.check=false" --save-prefs

prefs: extract portable/preferences.txt.orig

portable/sketchbook/sonoff/user_config_override.h:
	$(info 11 Adding user_config_override.h)
	ln -s ../../user_config_override.h portable/sketchbook/sonoff/user_config_override.h
	sed -i '/\/\/#define USE_CONFIG_OVERRIDE/s/\/\///' Sonoff-Tasmota/sonoff/my_user_config.h

config: extract src portable/sketchbook/sonoff/user_config_override.h

install-ide: extract board

deploy-sketch: install-ide src tune tool prefs config

run: deploy-sketch
	$(info 12 Running Arduino IDE)
	./arduino portable/sketchbook/sonoff/sonoff.ino &

build/sonoff.bin: build
	./arduino portable/sketchbook/sonoff/sonoff.ino --pref "build.path=/tmp/build" \
	                                                --pref "build.project_name=$(patsubst build/%.bin,%,$@)" \
	                                                --verbose-build \
	                                                --verify && \
	                                                cp /tmp/$@ ./$@

build/sonoff-minimal.bin: build
	./arduino portable/sketchbook/sonoff/sonoff.ino --pref "build.path=/tmp/build" \
	                                                --pref "build.project_name=$(patsubst build/%.bin,%,$@)" \
	                                                --pref "build.extra_flags=-DFIRMWARE_MINIMAL" \
	                                                --verbose-build \
	                                                --verify && \
	                                                cp /tmp/$@ ./$@

build/esp.bin: build
	./arduino portable/sketchbook/sonoff/sonoff.ino --pref "build.path=/tmp/build" \
	                                                --pref "build.project_name=$(patsubst build/%.bin,%,$@)" \
	                                                --pref "build.extra_flags=-DWITH_STA1 -DESP_CONFIG" \
	                                                --verbose-build \
	                                                --verify && \
	                                                cp /tmp/$@ ./$@

build/esp-minimal.bin: build
	./arduino portable/sketchbook/sonoff/sonoff.ino --pref "build.path=/tmp/build" \
	                                                --pref "build.project_name=$(patsubst build/%.bin,%,$@)" \
	                                                --pref "build.extra_flags=-DWITH_STA1 -DESP_CONFIG -DFIRMWARE_MINIMAL" \
	                                                --verbose-build \
	                                                --verify && \
	                                                cp /tmp/$@ ./$@

espupload: build
	./arduino portable/sketchbook/sonoff/sonoff.ino --pref "build.path=/tmp/build" \
	                                                --pref "upload.project_name=sonoff" \
	                                                --pref "build.project_name={upload.project_name}" \
	                                                --pref "custom_UploadTool=generic_espupload" \
	                                                --verbose-upload \
	                                                --port /dev/null \
	                                                --upload

clean:
	rm -rf *.bin

bins: sonoff.bin sonoff-minimal.bin esp.bin esp-minimal.bin

scp: build/sonoff.bin build/sonoff-minimal.bin build/esp.bin build/esp-minimal.bin build/version.txt
# tasmota-server described in ~/.ssh/config
	scp $(wildcard build/*.bin) build/version.txt tasmota-server:/var/www/html/tasmota

ota-server: 
	python -m SimpleHTTPServer 8000
