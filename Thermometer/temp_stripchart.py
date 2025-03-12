import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import serial
import sys

# configure the serial port
ser = serial.Serial(
    port='COM4', 
    baudrate=115200, 
    parity=serial.PARITY_NONE, 
    stopbits=serial.STOPBITS_TWO, 
    bytesize=serial.EIGHTBITS
) 
ser.isOpen()

xsize = 100

def data_gen():
    t = data_gen.t
    while True:
        t += 1
        val = float(ser.readline().decode('utf-8').strip())  # Decode and strip newline
        yield t, val

def run(data):
    t, y = data
    if t > -1:
        xdata.append(t)
        ydata.append(y)

        # Change plot color based on the temperature
        if y < 20:  # Cold temperature (e.g., below 20°C)
            line.set_color('blue')
        elif 20 <= y <= 30:  # Normal temperature (e.g., between 20°C and 30°C)
            line.set_color('green')
        else:  # Hot temperature (e.g., above 30°C)
            line.set_color('red')

        # Scroll to the left if the time exceeds xsize
        if t > xsize:
            ax.set_xlim(t - xsize, t)
        line.set_data(xdata, ydata)

    return line,

def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line, = ax.plot([], [], lw=2)
ax.set_ylim(-100, 100)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Start the animation
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
