# Microcontroller-Projects

Reflow Oven Controller:

Designed and implemented a microcontroller-based control system for a solder reflow oven using the Nuvoton N76E003. Programmed a finite state machine in Assembly to control a solid-state relay, integrating a charge pump, op-amp, LCD, and pushbutton controls for selecting pre-set temperatures, improving user accessibility and process consistency.

Capacitance Meter:

Designed and built a capacitance meter using an astable 555 timer, constructed from fundamental logic components including comparators, NAND gates (SR flip-flop), a BJT, and a capacitor. The system was interfaced with an EFM8 microcontroller, which measured the oscillation frequency on T0/P0.0, calculated capacitance in real-time, and displayed values on an LCD screen.

AC Voltmeter

Designed and implemented an AC phasor voltmeter using the EFM8 microcontroller to measure the magnitude and phase difference of two sinusoidal signals. The system takes two analog inputs— a reference signal and a test signal— and processes them to compute RMS voltage, period, and phase angle. Edge detection was used to identify zero crossings, allowing for precise period and phase calculations. The measured values are displayed on an LCD, with user-selectable modes for viewing voltage, phase, or period. The microcontroller’s ADC captures input voltages, and a timer-based interrupt system ensures real-time data acquisition and processing.