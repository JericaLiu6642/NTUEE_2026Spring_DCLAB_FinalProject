This is the readme for Digital Circuit Lab, 2026 Spring.

Calibration procedure:

1. Remove the tracking magnet and keep the four sensors mounted together.
2. Press `KEY[0]` to begin collection. `LEDG[1]` indicates collection.
3. Slowly rotate the complete sensor assembly through all orientations so every
   sensor axis reaches both positive and negative extrema.
4. Press `KEY[1]` and wait for calculation to finish.
5. `LEDG[3]` means calibration succeeded. `LEDG[5]` means axis coverage was
   insufficient; repeat the procedure. Set `SW[4]=1` to use calibrated values.

75 Hz AC magnetic-field extraction:

- Each QMC5883P is read at a deterministic 200 samples per second.
- A one-second coherent lock-in window extracts the 75 Hz X/Y/Z components.
- The VGA graph displays the 75 Hz vector L2 norm squared in Q16.16 Gauss^2.
- `LEDG[4]` pulses whenever a new one-second lock-in result is available.
- UART and the numeric X/Y/Z displays continue to show the selected raw or
  calibrated time-domain samples.
