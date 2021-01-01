#include "ps_fastmem.h"

#include <assert.h>
#include <endian.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ps_mappings.h"
#include "ps_protocol.h"
#include "psconf.h"

unsigned char fastmem[FASTMEM_SIZE];

#if !FASTMEM_FASTPATH
static unsigned int fastmem_read_8(unsigned int address) {
  return fastmem[address - FASTMEM_BASE];
}

static unsigned int fastmem_read_16(unsigned int address) {
  return be16toh(*(uint16_t *)&fastmem[address - FASTMEM_BASE]);
}

static unsigned int fastmem_read_32(unsigned int address) {
  return be32toh(*(uint32_t *)&fastmem[address - FASTMEM_BASE]);
}

static void fastmem_write_8(unsigned int address, unsigned int value) {
  fastmem[address - FASTMEM_BASE] = value;
}

static void fastmem_write_16(unsigned int address, unsigned int value) {
  *(uint16_t *)&fastmem[address - FASTMEM_BASE] = htobe16(value);
}

static void fastmem_write_32(unsigned int address, unsigned int value) {
  *(uint32_t *)&fastmem[address - FASTMEM_BASE] = htobe32(value);
}
#endif

void init_fastmem() {
#if !FASTMEM_FASTPATH
  struct ps_device fastmem_device = {
      fastmem_read_8, fastmem_read_16, fastmem_read_32,
      fastmem_write_8, fastmem_write_16, fastmem_write_32};

  unsigned int devno = ps_add_device(&fastmem_device);
  ps_add_range(devno, FASTMEM_BASE, FASTMEM_SIZE);
#endif
}
