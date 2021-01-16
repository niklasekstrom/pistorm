#include "ps_irq.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "m68k.h"
#include "ps_customchips.h"
#include "ps_mappings.h"
#include "ps_protocol.h"
#include "psconf.h"

static struct ps_irq_device int2_devices[MAX_INT2_DEVICES];
static int int2_device_count = 0;

static unsigned int intena_shadow = 0;

#define INT2_ENABLED() ((intena_shadow & (INTF_INTEN | INTF_PORTS)) == (INTF_INTEN | INTF_PORTS))

static unsigned int emu_int2_req() {
  for (int i = 0; i < int2_device_count; i++) {
    if (int2_devices[i].check_irq())
      return 1;
  }
  return 0;
}

unsigned int read_intenar() {
  unsigned int value = ps_read_16(INTENAR);
  intena_shadow = value;
  return value;
}

unsigned int read_intreqr() {
  unsigned int value = ps_read_16(INTREQR);

  if (emu_int2_req())
    value |= INTF_PORTS;

  return value;
}

void write_intena(unsigned int value) {
  ps_write_16(INTENA, value);

  if (value & INTF_SETCLR)
    intena_shadow |= value & (~INTF_SETCLR);
  else
    intena_shadow &= ~value;
}

void ps_set_irq() {
  unsigned int ipl = 0;

  if (!ps_get_aux1()) {
    unsigned int status = ps_read_status_reg();
    ipl = (status & 0xe000) >> 13;
  }

  if (ipl < 2 && INT2_ENABLED() && emu_int2_req()) {
    ipl = 2;
  }

  m68k_set_irq(ipl);
}

void ps_add_int2_device(struct ps_irq_device *device) {
  if (int2_device_count == MAX_INT2_DEVICES) {
    printf("No more slots left for INT2 irq devices, max=%d\n", MAX_INT2_DEVICES);
    exit(-1);
  }

  int2_devices[int2_device_count++] = *device;
}
