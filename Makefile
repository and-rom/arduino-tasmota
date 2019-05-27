.DEFAULT_GOAL := deploy-sketch

.PHONY:  download extract dirs board repo libs src tune tool prefs config install-ide deploy-sketch run bins scp ota-server clean clean-all clean-config
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
	./arduino --install-boards esp8266:esp8266:2.5.1

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

portable/packages/esp8266/hardware/esp8266/2.5.1/boards.txt.orig:
	$(info 8.1 Tuning board)
	mv portable/packages/esp8266/hardware/esp8266/2.5.1/boards.txt portable/packages/esp8266/hardware/esp8266/2.5.1/boards.txt.orig
	ln -s "../../../../../../Sonoff-Tasmota/arduino/version 2.5.1/boards.txt" "portable/packages/esp8266/hardware/esp8266/2.5.1/boards.txt"

portable/packages/esp8266/hardware/esp8266/2.5.1/platform.txt.orig:
	$(info 8.2 Tuning board)
	mv portable/packages/esp8266/hardware/esp8266/2.5.1/platform.txt portable/packages/esp8266/hardware/esp8266/2.5.1/platform.txt.orig
	ln -s "../../../../../../Sonoff-Tasmota/arduino/version 2.5.1/platform.txt" "portable/packages/esp8266/hardware/esp8266/2.5.1/platform.txt"

tune: portable/packages/esp8266/hardware/esp8266/2.5.1/boards.txt.orig \
	portable/packages/esp8266/hardware/esp8266/2.5.1/platform.txt.orig \
	board src

portable/packages/esp8266/hardware/esp8266/2.5.1/tools/espupload.py:
	$(info 9 Adding upload tool)
	ln -s "../../../../../../../Sonoff-Tasmota/arduino/espupload.py" "portable/packages/esp8266/hardware/esp8266/2.5.1/tools/espupload.py"

tool: board src portable/packages/esp8266/hardware/esp8266/2.5.1/tools/espupload.py

portable/preferences.txt.orig:
	$(info 10 Setting board type, build parameters and IDE preferences)
	cp portable/preferences.txt portable/preferences.txt.orig
    #baud=57600          # Upload Speed
    #UploadTool=esptool  # Upload Tool (Serial = esptool, OTA_upload = espupload)
    #xtal=80             # CPU Frequency
    #CrystalFreq=26      # Crystal Frequency
    #eesz=1M             # Flash Size
    #FlashMode=dout      # Flash Mode
    #FlashFreq=40        # Flash Frequency
    #ResetMethod=nodemcu # Reset Method
    #dbg=Disabled        # Debug Port
    #lvl=None____        # Debug Level
    #ip=lm2f             # lwIPVariant
    #vt=flash            # VTables
    #exception=disabled  # Exception
    #led=2"              # Builtin Led
    #wipe=none           # Erase Flash (Only Sketch = none)
	./arduino --board  "esp8266:esp8266:generic:\
                    baud=57600,\
                    UploadTool=esptool,\
                    xtal=80,\
                    CrystalFreq=26,\
                    eesz=1M,\
                    FlashMode=dout,\
                    FlashFreq=40,\
                    ResetMethod=nodemcu,\
                    dbg=Disabled,\
                    lvl=None____,\
                    ip=lm2f,\
                    vt=flash,\
                    exception=disabled,\
                    led=2,\
                    wipe=none"\
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
	rm -rf build/*.bin

clean-all:
	rm -rf $(filter-out Makefile user_config_override.h,$(wildcard *))

clean-config:
	rm -rf Sonoff-Tasmota/sonoff/user_config_override.h


bins: sonoff.bin sonoff-minimal.bin esp.bin esp-minimal.bin
build/version.txt: build
	$(eval VER := $(shell cat Sonoff-Tasmota/sonoff/sonoff_version.h | sed -ne "s#^.*VERSION = \\(.*\\);#\1#p"))
	$(eval STR_VER :=$(shell printf '%d.%d.%d' "$$(( $$(( $(VER) >> 24 )) & 0xFF ))" "$$(( $$(( $(VER) >> 16 )) & 0xFF ))" "$$(( $$(( $(VER) >> 8 )) & 0xFF ))" ))
	$(eval STR_VER :=$(shell [ $$(( $(VER) & 0xFF)) -ne 0 ] && printf '%s.%d' $(STR_VER) "$$(( $(VER) & 0xFF ))" || echo $(STR_VER)))
	echo $(STR_VER) > build/version.txt

scp: build/sonoff.bin build/sonoff-minimal.bin build/esp.bin build/esp-minimal.bin build/version.txt
# tasmota-server described in ~/.ssh/config
	scp $(wildcard build/*.bin) build/version.txt tasmota-server:/var/www/html/tasmota

ota-server:
	python -m SimpleHTTPServer 8000
