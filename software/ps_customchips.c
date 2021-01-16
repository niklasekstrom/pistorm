#include "ps_customchips.h"

#include "ps_irq.h"
#include "ps_mappings.h"
#include "ps_protocol.h"
#include "psconf.h"

static unsigned int cc_read_8(unsigned int address) {
  return ps_read_8(address);
}

static unsigned int cc_read_16(unsigned int address) {
  if (address == INTENAR)
    return read_intenar();
  else if (address == INTREQR)
    return read_intreqr();
  else
    return ps_read_16(address);
}

static unsigned int cc_read_32(unsigned int address) {
  unsigned int a = cc_read_16(address);
  unsigned int b = cc_read_16(address + 2);
  return (a << 16) | b;
}

static void cc_write_8(unsigned int address, unsigned int value) {
  ps_write_8(address, value);
}

static void cc_write_16(unsigned int address, unsigned int value) {
  if (address == INTENA)
    write_intena(value);
  else
    ps_write_16(address, value);
}

static void cc_write_32(unsigned int address, unsigned int value) {
  cc_write_16(address, value >> 16);
  cc_write_16(address + 2, value);
}

int init_customchips() {
  struct ps_device cc_device = {
      cc_read_8, cc_read_16, cc_read_32,
      cc_write_8, cc_write_16, cc_write_32};

  unsigned int devno = ps_add_device(&cc_device);
  ps_add_range(devno, 0xdf0000, 0x10000);
  return 0;
}
