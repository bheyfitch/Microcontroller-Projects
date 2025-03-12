// CapacitanceMeter.c: Measure the frequency of a signal on pin T0/P0.0 and calculate capacitance based on the measured frequency.
//
// The next line clears the "C51 command line options:" field when compiling with CrossIDE
//  ~C51~

#include <EFM8LB1.h>
#include <stdio.h>
#include <string.h> // Required for string functions

#define SYSCLK 72000000L // SYSCLK frequency in Hz
#define BAUDRATE 115200L // Baud rate of UART in bps

#define LCD_RS P1_7
#define LCD_E P2_0
#define LCD_D4 P1_3
#define LCD_D5 P1_2
#define LCD_D6 P1_1
#define LCD_D7 P1_0
#define CHARS_PER_LINE 16

unsigned char overflow_count = 0;
unsigned long F;
unsigned long testCounter = 0;
unsigned long secondsCounter = 0;

char _c51_external_startup(void)
{
	// Disable Watchdog with key sequence
	SFRPAGE = 0x00;
	WDTCN = 0xDE; // First key
	WDTCN = 0xAD; // Second key

	VDM0CN |= 0x80;
	RSTSRC = 0x02;

#if (SYSCLK == 48000000L)
	SFRPAGE = 0x10;
	PFE0CN = 0x10; // SYSCLK < 50 MHz.
	SFRPAGE = 0x00;
#elif (SYSCLK == 72000000L)
	SFRPAGE = 0x10;
	PFE0CN = 0x20; // SYSCLK < 75 MHz.
	SFRPAGE = 0x00;
#endif

#if (SYSCLK == 12250000L)
	CLKSEL = 0x10;
	CLKSEL = 0x10;
	while ((CLKSEL & 0x80) == 0)
		;
#elif (SYSCLK == 24500000L)
	CLKSEL = 0x00;
	CLKSEL = 0x00;
	while ((CLKSEL & 0x80) == 0)
		;
#elif (SYSCLK == 48000000L)
	// Before setting clock to 48 MHz, must transition to 24.5 MHz first
	CLKSEL = 0x00;
	CLKSEL = 0x00;
	while ((CLKSEL & 0x80) == 0)
		;
	CLKSEL = 0x07;
	CLKSEL = 0x07;
	while ((CLKSEL & 0x80) == 0)
		;
#elif (SYSCLK == 72000000L)
	// Before setting clock to 72 MHz, must transition to 24.5 MHz first
	CLKSEL = 0x00;
	CLKSEL = 0x00;
	while ((CLKSEL & 0x80) == 0)
		;
	CLKSEL = 0x03;
	CLKSEL = 0x03;
	while ((CLKSEL & 0x80) == 0)
		;
#else
#error SYSCLK must be either 12250000L, 24500000L, 48000000L, or 72000000L
#endif

	P0MDOUT |= 0x10; // Enable UART0 TX as push-pull output
	XBR0 = 0x01;	 // Enable UART0 on P0.4(TX) and P0.5(RX)
	XBR1 = 0X10;	 // Enable T0 on P0.0
	XBR2 = 0x40;	 // Enable crossbar and weak pull-ups

#if (((SYSCLK / BAUDRATE) / (2L * 12L)) > 0xFFL)
#error Timer 0 reload value is incorrect because (SYSCLK/BAUDRATE)/(2L*12L) > 0xFF
#endif
	// Configure Uart 0
	SCON0 = 0x10;
	CKCON0 |= 0b_0000_0000; // Timer 1 uses the system clock divided by 12.
	TH1 = 0x100 - ((SYSCLK / BAUDRATE) / (2L * 12L));
	TL1 = TH1;	   // Init Timer1
	TMOD &= ~0xf0; // TMOD: timer 1 in 8-bit auto-reload
	TMOD |= 0x20;
	TR1 = 1; // START Timer1
	TI = 1;	 // Indicate TX0 ready

	TMR2CN0 = 0x00;   // Stop Timer2; Clear TF2;
	CKCON0 |= 0b_0001_0000; // Timer 2 uses the system clock
	TMR2RL = (0x10000L - (SYSCLK / (2000L))); // Initialize reload value
	TMR2 = 0xffff;  // Set to reload immediately
	ET2 = 1;        // Enable Timer2 interrupts
	TR2 = 1;        // Start Timer2 (TMR2CN is bit addressable)
	ET0 = 1;		// Enable Timer 0 interrupts
	EA = 1; 		// Enable interrupts

	return 0;
}

// Uses Timer3 to delay <us> micro-seconds.
void Timer3us(unsigned char us)
{
	unsigned char i; // usec counter

	// The input for Timer 3 is selected as SYSCLK by setting T3ML (bit 6) of CKCON0:
	CKCON0 |= 0b_0100_0000;

	TMR3RL = (-(SYSCLK) / 1000000L); // Set Timer3 to overflow in 1us.
	TMR3 = TMR3RL;					 // Initialize Timer3 for first overflow

	TMR3CN0 = 0x04;			 // Sart Timer3 and clear overflow flag
	for (i = 0; i < us; i++) // Count <us> overflows
	{
		while (!(TMR3CN0 & 0x80))
			;				// Wait for overflow
		TMR3CN0 &= ~(0x80); // Clear overflow indicator

	}
	TMR3CN0 = 0; // Stop Timer3 and clear overflow flag
}

void Timer2_ISR(void) interrupt INTERRUPT_TIMER2
{
	SFRPAGE = 0x0;
	TF2H = 0; // Clear Timer2 interrupt flag

	testCounter++; // Keeps track of number of interrupts; if it is 2000, then 1 second has passed

	if (testCounter == 2000) {
		F = (overflow_count * 0x10000L + TH0 * 0x100L + TL0); // Calculates frequency
		testCounter = 0; // Resets testCounter
		secondsCounter++; // For testing, increments secondsCounter to see if it increments every second as intended
		overflow_count = 0; //Resets overflow_count
		TH0 = 0; // Resets the high byte of Timer 0
		TL0 = 0; // Resets the low byte of Timer 0
	}
}

void waitms(unsigned int ms)
{
	unsigned int j;
	for (j = ms; j != 0; j--)
	{
		Timer3us(249);
		Timer3us(249);
		Timer3us(249);
		Timer3us(250);
	}
}

void TIMER0_Init(void)
{
	TMOD &= 0b_1111_0000; // Set the bits of Timer/Counter 0 to zero
	TMOD |= 0b_0000_0101; // Timer/Counter 0 used as a 16-bit counter
	TF0 = 0;
	TR0 = 1;			  // Start Timer/Counter 0

}

void Timer0_ISR(void) interrupt INTERRUPT_TIMER0
{
	SFRPAGE = 0x0;

	overflow_count++; //Increments overflow_count every time there is an interrupt (which only occurs when Timer 0 overflows)
}

void LCD_pulse(void)
{
	LCD_E = 1;
	Timer3us(40);
	LCD_E = 0;
}

void LCD_byte(unsigned char x)
{
	// The accumulator in the C8051Fxxx is bit addressable!
	ACC = x; // Send high nible
	LCD_D7 = ACC_7;
	LCD_D6 = ACC_6;
	LCD_D5 = ACC_5;
	LCD_D4 = ACC_4;
	LCD_pulse();
	Timer3us(40);
	ACC = x; // Send low nible
	LCD_D7 = ACC_3;
	LCD_D6 = ACC_2;
	LCD_D5 = ACC_1;
	LCD_D4 = ACC_0;
	LCD_pulse();
}

void WriteData(unsigned char x)
{
	LCD_RS = 1;
	LCD_byte(x);
	waitms(1);
}

void WriteCommand(unsigned char x)
{
	LCD_RS = 0;
	LCD_byte(x);
	waitms(1);
}

void LCD_4BIT(void)
{
	LCD_E = 0; // Resting state of LCD's enable is zero
	// LCD_RW=0; // We are only writing to the LCD in this program
	waitms(20);
	// First make sure the LCD is in 8-bit mode and then change to 4-bit mode
	WriteCommand(0x33);
	WriteCommand(0x33);
	WriteCommand(0x32); // Change to 4-bit mode

	// Configure the LCD
	WriteCommand(0x28);
	WriteCommand(0x0c);
	WriteCommand(0x01); // Clear screen command (takes some time)
	waitms(20);			// Wait for clear screen command to finsih.
}

void LCDprint(char* string, unsigned char line, bit clear)
{
	int j;

	WriteCommand(line == 2 ? 0xc0 : 0x80);
	waitms(5);
	for (j = 0; string[j] != 0; j++)
		WriteData(string[j]); // Write the message
	if (clear)
		for (; j < CHARS_PER_LINE; j++)
			WriteData(' '); // Clear the rest of the line
}

int toggleState(void) {
	static int state = 0; // Initialize state as 0, static so that it isn't just always being set to 0 when the function is called
	if (!P0_5) {
		waitms(50); // Wait 40ms then check again if the button is still pressed for debouncing
		if (!P0_5) {
			state = (state + 1) % 4; //We only have three possible states; 0, 1, and 2, so taking the modulo of state+1 with 3 keeps it below 3
		}
	}
	return state;
}

void main(void)
{
	float cap; // Capacitance Value in nF
	char capString[15];
	char textString[10];
	int state;

	TIMER0_Init();
	// Configure the LCD
	LCD_4BIT();

	waitms(100);	   // Give PuTTY a chance to start.
	printf("\x1b[2J"); // Clear screen using ANSI escape sequence.

	printf("EFM8 Frequency measurement using Timer/Counter 0.\n"
		"File: %s\n"
		"Compiled: %s, %s\n\n",
		__FILE__, __DATE__, __TIME__);

	while (1) //Runs forever, constant/infinite loop
	{

		cap = 283076.923077 / F; // 283076.918722 is just 1440000000 / (3 * 1695.6522), precomputed for speed since its a constant

		state = toggleState(); // Function for toggling what is displayed by pushing the button

		printf("\r Frequency = %lu Hz \n", F);
		printf("\r Capacitance = %f nF \n", cap);
		printf("\r Time Elapsed = %lu s \n", secondsCounter);
		printf("\r State = %i \n\n", state);
		printf("\x1b[0K"); // ANSI: Clear from cursor to end of line.


		if (state == 0) {
			sprintf(capString, "%.3f", cap); // Store the capacitance with 3 decimal points as a string
			strcpy(textString, " nF"); // Store the string "nF"
			strcat(capString, textString); //Concatenate the capacitance string with  " nF"

			LCDprint(capString, 2, 1); // Display the capacitance on the second row of the LCD
			LCDprint("Capacitance:", 1, 1); //Display the text "Capacitance:" on the first row of the LCD
		}

		else if (state == 1) {
			sprintf(capString, "%.6f", cap / 1000); // Store the capacitance with 6 decimal points as a string
			strcpy(textString, " uF"); // Store the string " uF"
			strcat(capString, textString); //Concatenate the capacitance string with  " uF"

			LCDprint(capString, 2, 1); // Display the capacitance on the second row of the LCD
			LCDprint("Capacitance:", 1, 1); //Display the text "Capacitance:" on the first row of the LCD
		}

		else if (state == 2) {
			sprintf(capString, "%lu", F); // Store the frequency as a string
			strcpy(textString, " Hz"); // Store the string " Hz"
			strcat(capString, textString); //Concatenate the capacitance string with  " Hz"

			LCDprint(capString, 2, 1); // Display the frequency on the second row of the LCD
			LCDprint("Frequency:", 1, 1); //Display the text "Frequency:" on the first row of the LCD
		}

		else {
			sprintf(capString, "%f", (float)1000 / F); // Store the period in ms as a string
			strcpy(textString, " ms"); // Store the string " ms"
			strcat(capString, textString); //Concatenate the capacitance string with  " ms"

			LCDprint(capString, 2, 1); // Display the period on the second row of the LCD
			LCDprint("Period:", 1, 1); //Display the text "Period: " on the first row of the LCD
		}
	}
}
