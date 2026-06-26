# deepcool_digital_dart

Unofficial GPLv3 Dart port of `deepcool-digital-linux`, focused first on the
DeepCool CH170 DIGITAL case display.

Upstream reference:
https://github.com/Nortank12/deepcool-digital-linux

This is not official DeepCool software.

## Current CH170 support

Best-supported modes:

- `cpu_freq`: CPU temperature, CPU power, CPU usage, and CPU frequency.
- `gpu`: GPU temperature, GPU power, GPU usage, and GPU frequency.
- `auto`: cycles between `cpu_freq` and `gpu`.

Recognized but limited modes:

- `cpu_fan`: uses the CH170 CPU/fan display layout, but fan RPM is not implemented yet.
- `psu`: uses the CH170 PSU display layout, but PSU telemetry is not implemented yet.

The default target is CH170 DIGITAL, vendor `0x3633`, product ID `19`
(`0x0013`). CH270 (`22`) and CH690 (`27`) use the same CH-series-gen2 packet
layout and can be selected with `--pid`, but this port is tuned and documented
for CH170 first.

## Requirements

- Linux.
- Dart SDK. In this workspace you can use:
  `../flutter/bin/dart`
- HIDAPI runtime library:
  - Arch: `sudo pacman -S hidapi`
  - Debian/Ubuntu: `sudo apt install libhidapi-hidraw0`
  - Fedora: `sudo dnf install hidapi`
- Root access, or a udev rule that allows your user to write to the DeepCool
  HID raw device.

NVIDIA GPU mode uses `libnvidia-ml.so` through Dart FFI when available. AMD and
Intel GPU mode use Linux sysfs.

## Run

From this package directory:

```bash
cd /home/rahngamingstudio/development/deepcool_digital_dart
../flutter/bin/dart run bin/deepcool_digital_dart.dart --help
```

Check that the CH170 packet can be built without touching USB:

```bash
../flutter/bin/dart run bin/deepcool_digital_dart.dart --dry-run
```

List DeepCool HID devices:

```bash
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --list
```

Run the CH170 in the recommended CPU mode:

```bash
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --mode cpu_freq
```

Run GPU mode:

```bash
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --mode gpu
```

If you have multiple GPUs, list them and choose one:

```bash
../flutter/bin/dart run bin/deepcool_digital_dart.dart --gpulist
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --mode gpu --gpuid nvidia:1
```

Use auto mode:

```bash
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --mode auto
```

Send one HID report and exit:

```bash
sudo ../flutter/bin/dart run bin/deepcool_digital_dart.dart --once
```

## Rootless udev rule

Create `/etc/udev/rules.d/99-deepcool-digital.rules`:

```udev
# DeepCool CH170 DIGITAL hidraw access
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0013", MODE="0666"

# Optional CPU power readout for Intel RAPL
ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0", RUN+="/bin/chmod 444 /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj"
```

Then reload rules and replug the CH170 USB connection or reboot:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Build native executable

```bash
cd /home/rahngamingstudio/development/deepcool_digital_dart
../flutter/bin/dart compile exe bin/deepcool_digital_dart.dart -o deepcool-digital-dart
sudo ./deepcool-digital-dart --mode cpu_freq
```

## Systemd service example

After compiling and placing the binary somewhere stable, create
`/etc/systemd/system/deepcool-digital-dart.service`:

```ini
[Unit]
Description=DeepCool Digital Dart CH170
After=multi-user.target

[Service]
ExecStart=/home/rahngamingstudio/development/deepcool_digital_dart/deepcool-digital-dart --mode auto
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deepcool-digital-dart
```

## Development checks

```bash
../flutter/bin/dart format .
../flutter/bin/dart analyze
../flutter/bin/dart run bin/deepcool_digital_dart.dart --dry-run
```

## License

GPL-3.0. See `LICENSE` and `NOTICE`.
