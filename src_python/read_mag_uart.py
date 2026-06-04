#!/usr/bin/env python3
import argparse
from collections import deque
import csv
import re
import sys
import time

try:
    import serial
except ImportError:
    print("Missing dependency: pyserial. Install with: pip install pyserial", file=sys.stderr)
    raise


LINE_RE = re.compile(
    r"^S(?P<sensor>[1-4]) "
    r"X=(?P<x>[+-][0-9A-Fa-f]{4}) "
    r"Y=(?P<y>[+-][0-9A-Fa-f]{4}) "
    r"Z=(?P<z>[+-][0-9A-Fa-f]{4})$"
)


def signed_hex_to_int(value: str) -> int:
    sign = -1 if value[0] == "-" else 1
    return sign * int(value[1:], 16)


def parse_line(line: str):
    match = LINE_RE.match(line)
    if not match:
        return None

    return {
        "sensor": int(match.group("sensor")),
        "x": signed_hex_to_int(match.group("x")),
        "y": signed_hex_to_int(match.group("y")),
        "z": signed_hex_to_int(match.group("z")),
        "raw_line": line,
    }


class LivePlot:
    def __init__(self, window_seconds: float):
        try:
            import matplotlib.pyplot as plt
        except ImportError:
            print(
                "Missing dependency: matplotlib. Install with: pip install matplotlib",
                file=sys.stderr,
            )
            raise

        self.plt = plt
        self.window_seconds = window_seconds
        self.start_time = time.time()
        self.history = {
            sensor: {
                "t": deque(),
                "x": deque(),
                "y": deque(),
                "z": deque(),
            }
            for sensor in range(1, 5)
        }

        plt.ion()
        self.figure, axes = plt.subplots(4, 1, sharex=True, figsize=(10, 8))
        self.axes = list(axes)
        self.lines = {}

        for sensor, axis in enumerate(self.axes, start=1):
            axis.set_ylabel(f"S{sensor}")
            axis.grid(True)
            self.lines[(sensor, "x")] = axis.plot([], [], label="X")[0]
            self.lines[(sensor, "y")] = axis.plot([], [], label="Y")[0]
            self.lines[(sensor, "z")] = axis.plot([], [], label="Z")[0]
            axis.legend(loc="upper right")

        self.axes[-1].set_xlabel("Time (s)")
        self.figure.suptitle("Four Magnetometer Sensor Output")
        self.figure.tight_layout()
        self.figure.show()

    def add_sample(self, parsed):
        now = time.time() - self.start_time
        sensor = parsed["sensor"]
        values = self.history[sensor]
        values["t"].append(now)
        values["x"].append(parsed["x"])
        values["y"].append(parsed["y"])
        values["z"].append(parsed["z"])

        cutoff = now - self.window_seconds
        while values["t"] and values["t"][0] < cutoff:
            values["t"].popleft()
            values["x"].popleft()
            values["y"].popleft()
            values["z"].popleft()

    def update(self):
        now = time.time() - self.start_time
        x_min = max(0.0, now - self.window_seconds)
        x_max = max(self.window_seconds, now)

        for sensor, axis in enumerate(self.axes, start=1):
            values = self.history[sensor]
            times = list(values["t"])
            for component in ("x", "y", "z"):
                self.lines[(sensor, component)].set_data(
                    times, list(values[component])
                )

            axis.set_xlim(x_min, x_max)
            axis.relim()
            axis.autoscale_view(scalex=False, scaley=True)

        self.figure.canvas.draw_idle()
        self.plt.pause(0.001)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read four-sensor magnetometer data from FPGA RS232 UART."
    )
    parser.add_argument(
        "port",
        help="Serial port, e.g. COM3 on Windows or /dev/ttyUSB0 on Linux.",
    )
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--csv", help="Optional CSV output file.")
    parser.add_argument(
        "--print-raw",
        action="store_true",
        help="Print raw serial lines instead of parsed decimal values.",
    )
    parser.add_argument(
        "--plot",
        action="store_true",
        help="Plot live X/Y/Z traces for all four sensors.",
    )
    parser.add_argument(
        "--plot-window",
        type=float,
        default=10.0,
        help="Live plot time window in seconds.",
    )
    parser.add_argument(
        "--plot-update-hz",
        type=float,
        default=60.0,
        help="Maximum Matplotlib redraw rate while plotting.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Do not print parsed samples to the terminal.",
    )
    args = parser.parse_args()

    csv_file = None
    writer = None
    if args.csv:
        csv_file = open(args.csv, "w", newline="", encoding="utf-8")
        writer = csv.DictWriter(
            csv_file,
            fieldnames=["timestamp", "sensor", "x", "y", "z", "raw_line"],
            )
        writer.writeheader()

    live_plot = LivePlot(args.plot_window) if args.plot else None
    last_plot_update = 0.0
    last_csv_flush = time.time()
    plot_update_period = 1.0 / args.plot_update_hz if args.plot_update_hz > 0 else 0.0

    try:
        with serial.Serial(args.port, args.baud, timeout=1) as ser:
            print(f"Reading {args.port} at {args.baud} baud. Press Ctrl-C to stop.")

            while True:
                data = ser.readline()
                if not data:
                    continue

                line = data.decode("ascii", errors="replace").strip()
                if not line:
                    continue

                parsed = parse_line(line)

                should_print = not args.quiet and (not args.plot or args.print_raw)

                if should_print and (args.print_raw or parsed is None):
                    print(line)
                elif should_print and parsed is not None:
                    print(
                        f"S{parsed['sensor']} "
                        f"X={parsed['x']:6d} "
                        f"Y={parsed['y']:6d} "
                        f"Z={parsed['z']:6d}"
                    )

                if writer and parsed is not None:
                    writer.writerow(
                        {
                            "timestamp": time.time(),
                            "sensor": parsed["sensor"],
                            "x": parsed["x"],
                            "y": parsed["y"],
                            "z": parsed["z"],
                            "raw_line": parsed["raw_line"],
                        }
                    )

                    now = time.time()
                    if now - last_csv_flush > 0.5:
                        csv_file.flush()
                        last_csv_flush = now

                if live_plot and parsed is not None:
                    live_plot.add_sample(parsed)
                    now = time.time()
                    if now - last_plot_update >= plot_update_period:
                        live_plot.update()
                        last_plot_update = now

    except KeyboardInterrupt:
        print("\nStopped.")
        return 0
    finally:
        if csv_file:
            csv_file.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
