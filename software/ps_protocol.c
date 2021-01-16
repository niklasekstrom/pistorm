#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define PIN_AUX0 0
#define PIN_AUX1 1

#define PIN_SA2 2
#define PIN_SA1 3
#define PIN_SA0 5

#define PIN_SOE 6
#define PIN_SWE 7

#define PIN_SD(x) (8 + x)

/*
 * Register addresses (from CPLD RTL):
 * 
 * Write16    0
 * Read16     1
 * Write8     2
 * Read8      3
 * Status     4
 */

#define STATUS_BIT_INIT 1
#define STATUS_BIT_RESET 2

#define STATUS_MASK_IPL 0xe000
#define STATUS_SHIFT_IPL 13

//#define BCM2708_PERI_BASE 0x20000000  // pi0-1
//#define BCM2708_PERI_BASE	0xFE000000  // pi4
#define BCM2708_PERI_BASE 0x3F000000  // pi3
#define BCM2708_PERI_SIZE 0x01000000

#define GPIO_ADDR 0x200000 /* GPIO controller */
#define GPCLK_ADDR 0x101000

#define GPIO_BASE (BCM2708_PERI_BASE + 0x200000) /* GPIO controller */
#define GPCLK_BASE (BCM2708_PERI_BASE + 0x101000)

#define CLK_PASSWD 0x5a000000
#define CLK_GP0_CTL 0x070
#define CLK_GP0_DIV 0x074

// GPIO setup macros. Always use INP_GPIO(x) before using OUT_GPIO(x) or
// SET_GPIO_ALT(x,y)
#define INP_GPIO(g) *(gpio + ((g) / 10)) &= ~(7 << (((g) % 10) * 3))
#define OUT_GPIO(g) *(gpio + ((g) / 10)) |= (1 << (((g) % 10) * 3))
#define SET_GPIO_ALT(g, a)  \
  *(gpio + (((g) / 10))) |= \
      (((a) <= 3 ? (a) + 4 : (a) == 4 ? 3 : 2) << (((g) % 10) * 3))

#define GPIO_PULL *(gpio + 37)      // Pull up/pull down
#define GPIO_PULLCLK0 *(gpio + 38)  // Pull up/pull down clock

volatile unsigned int *gpio;
volatile unsigned int *gpclk;

unsigned int gpfsel0;
unsigned int gpfsel1;
unsigned int gpfsel2;

unsigned int gpfsel0_o;
unsigned int gpfsel1_o;
unsigned int gpfsel2_o;

static void setup_io() {
  int fd = open("/dev/mem", O_RDWR | O_SYNC);
  if (fd < 0) {
    printf("Unable to open /dev/mem. Run as root using sudo?\n");
    exit(-1);
  }

  void *gpio_map = mmap(
      NULL,                    // Any adddress in our space will do
      BCM2708_PERI_SIZE,       // Map length
      PROT_READ | PROT_WRITE,  // Enable reading & writting to mapped memory
      MAP_SHARED,              // Shared with other processes
      fd,                      // File to map
      BCM2708_PERI_BASE        // Offset to GPIO peripheral
  );

  close(fd);

  if (gpio_map == MAP_FAILED) {
    printf("mmap failed, errno = %d\n", errno);
    exit(-1);
  }

  gpio = ((volatile unsigned *)gpio_map) + GPIO_ADDR / 4;
  gpclk = ((volatile unsigned *)gpio_map) + GPCLK_ADDR / 4;
}

static void setup_gpclk() {
  // Enable 200MHz CLK output on GPIO4, adjust divider and pll source depending
  // on pi model
  *(gpclk + (CLK_GP0_CTL / 4)) = CLK_PASSWD | (1 << 5);
  usleep(10);
  while ((*(gpclk + (CLK_GP0_CTL / 4))) & (1 << 7))
    ;
  usleep(100);
  *(gpclk + (CLK_GP0_DIV / 4)) =
      CLK_PASSWD | (6 << 12);  // divider , 6=200MHz on pi3
  usleep(10);
  *(gpclk + (CLK_GP0_CTL / 4)) =
      CLK_PASSWD | 5 | (1 << 4);  // pll? 6=plld, 5=pllc
  usleep(10);
  while (((*(gpclk + (CLK_GP0_CTL / 4))) & (1 << 7)) == 0)
    ;
  usleep(100);

  SET_GPIO_ALT(4, 0);  // gpclk0
}

void ps_setup_protocol() {
  setup_io();
  setup_gpclk();

  INP_GPIO(PIN_AUX0);
  INP_GPIO(PIN_AUX1);

  INP_GPIO(PIN_SA2);
  OUT_GPIO(PIN_SA2);
  INP_GPIO(PIN_SA1);
  OUT_GPIO(PIN_SA1);
  INP_GPIO(PIN_SA0);
  OUT_GPIO(PIN_SA0);

  INP_GPIO(PIN_SOE);
  OUT_GPIO(PIN_SOE);

  INP_GPIO(PIN_SWE);
  OUT_GPIO(PIN_SWE);

  for (int i = 0; i < 16; i++) {
    INP_GPIO(PIN_SD(i));
    OUT_GPIO(PIN_SD(i));
  }

  // Precalculate SDx as Output
  gpfsel0_o = *(gpio);
  gpfsel1_o = *(gpio + 1);
  gpfsel2_o = *(gpio + 2);

  for (int i = 0; i < 16; i++) {
    INP_GPIO(PIN_SD(i));
  }

  // Precalculate SDx as Input
  gpfsel0 = *(gpio);
  gpfsel1 = *(gpio + 1);
  gpfsel2 = *(gpio + 2);

  *(gpio + 10) = 1 << PIN_SA2;
  *(gpio + 10) = 1 << PIN_SA1;
  *(gpio + 7) = 1 << PIN_SA0;

  *(gpio + 7) = 1 << PIN_SOE;
  *(gpio + 7) = 1 << PIN_SWE;
}

void ps_write_16(unsigned int address, unsigned int data) {
  *(gpio) = gpfsel0_o;
  *(gpio + 1) = gpfsel1_o;
  *(gpio + 2) = gpfsel2_o;

  *(gpio + 10) = (0xffff << 8) | (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = (address & 0xffff) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (address >> 16) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (data & 0xffff) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio) = gpfsel0;
  *(gpio + 1) = gpfsel1;
  *(gpio + 2) = gpfsel2;

  while (*(gpio + 13) & (1 << PIN_AUX0))
    ;
}

void ps_write_8(unsigned int address, unsigned int data) {
  if ((address & 1) == 0)
    data = data + (data << 8);  // EVEN, A0=0,UDS
  else
    data = data & 0xff;  // ODD , A0=1,LDS

  *(gpio) = gpfsel0_o;
  *(gpio + 1) = gpfsel1_o;
  *(gpio + 2) = gpfsel2_o;

  *(gpio + 10) = (0xffff << 8) | (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = ((address & 0xffff) << 8) | (1 << PIN_SA1);

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (address >> 16) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (data & 0xffff) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio) = gpfsel0;
  *(gpio + 1) = gpfsel1;
  *(gpio + 2) = gpfsel2;

  while (*(gpio + 13) & (1 << PIN_AUX0))
    ;
}

void ps_write_32(unsigned int address, unsigned int value) {
  ps_write_16(address, value >> 16);
  ps_write_16(address + 2, value);
}

unsigned int ps_read_16(unsigned int address) {
  *(gpio) = gpfsel0_o;
  *(gpio + 1) = gpfsel1_o;
  *(gpio + 2) = gpfsel2_o;

  *(gpio + 10) = (0xffff << 8) | (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = ((address & 0xffff) << 8) | (1 << PIN_SA0);

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (address >> 16) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio) = gpfsel0;
  *(gpio + 1) = gpfsel1;
  *(gpio + 2) = gpfsel2;

  *(gpio + 10) = 1 << PIN_SOE;

  while (!(*(gpio + 13) & (1 << PIN_AUX0)))
    ;

  *(gpio + 10) = 1 << PIN_SOE;

  int val = *(gpio + 13);

  *(gpio + 7) = 1 << PIN_SOE;

  return (val >> 8) & 0xffff;
}

unsigned int ps_read_8(unsigned int address) {
  *(gpio) = gpfsel0_o;
  *(gpio + 1) = gpfsel1_o;
  *(gpio + 2) = gpfsel2_o;

  *(gpio + 10) = (0xffff << 8) | (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = ((address & 0xffff) << 8) | (1 << PIN_SA1) | (1 << PIN_SA0);

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio + 10) = 0xffff << 8;
  *(gpio + 7) = (address >> 16) << 8;

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio) = gpfsel0;
  *(gpio + 1) = gpfsel1;
  *(gpio + 2) = gpfsel2;

  *(gpio + 10) = 1 << PIN_SOE;

  while (!(*(gpio + 13) & (1 << PIN_AUX0)))
    ;

  *(gpio + 10) = 1 << PIN_SOE;

  int val = *(gpio + 13);

  *(gpio + 7) = 1 << PIN_SOE;

  val = (val >> 8) & 0xffff;

  if ((address & 1) == 0)
    return (val >> 8) & 0xff;  // EVEN, A0=0,UDS
  else
    return val & 0xff;  // ODD , A0=1,LDS
}

unsigned int ps_read_32(unsigned int address) {
  unsigned int a = ps_read_16(address);
  unsigned int b = ps_read_16(address + 2);
  return (a << 16) | b;
}

void ps_write_status_reg(unsigned int value) {
  *(gpio) = gpfsel0_o;
  *(gpio + 1) = gpfsel1_o;
  *(gpio + 2) = gpfsel2_o;

  *(gpio + 10) = (0xffff << 8) | (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = ((value & 0xffff) << 8) | (1 << PIN_SA2);

  *(gpio + 10) = 1 << PIN_SWE;
  *(gpio + 10) = 1 << PIN_SWE;  // delay
  *(gpio + 7) = 1 << PIN_SWE;
  *(gpio + 7) = 1 << PIN_SWE;

  *(gpio) = gpfsel0;
  *(gpio + 1) = gpfsel1;
  *(gpio + 2) = gpfsel2;
}

unsigned int ps_read_status_reg() {
  *(gpio + 10) = (1 << PIN_SA2) | (1 << PIN_SA1) | (1 << PIN_SA0);
  *(gpio + 7) = (1 << PIN_SA2);

  *(gpio + 10) = 1 << PIN_SOE;
  *(gpio + 10) = 1 << PIN_SOE;
  *(gpio + 10) = 1 << PIN_SOE;
  *(gpio + 10) = 1 << PIN_SOE;

  unsigned int val = *(gpio + 13);

  *(gpio + 7) = 1 << PIN_SOE;

  return (val >> 8) & 0xffff;
}

void ps_reset_state_machine() {
  ps_write_status_reg(STATUS_BIT_INIT);
  usleep(1500);
  ps_write_status_reg(0);
  usleep(100);
}

void ps_pulse_reset() {
  ps_write_status_reg(0);
  usleep(100000);
  ps_write_status_reg(STATUS_BIT_RESET);
}

int ps_get_aux1() {
  unsigned int val = *(gpio + 13);
  return val & (1 << PIN_AUX1);
}
