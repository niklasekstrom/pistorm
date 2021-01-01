//
//  Gayle.c
//  Omega
//
//  Created by Matt Parsons on 06/03/2019.
//  Copyright © 2019 Matt Parsons. All rights reserved.
//
//  Changes made 2020 by Niklas Ekström to better fit PiStorm.

// Write Byte to Gayle Space 0xda9000 (0x0000c3)
// Read Byte From Gayle Space 0xda9000
// Read Byte From Gayle Space 0xdaa000

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "ide/ide.h"
#include "ps_mappings.h"

#define CLOCKBASE 0xDC0000

//#define GSTATUS 0xda201c
//#define GCLOW   0xda2010
//#define GDH	0xda2018

// Gayle Addresses

// Gayle IDE Reads
#define GERROR 0xda2004   // Error
#define GSTATUS 0xda201c  // Status
// Gayle IDE Writes
#define GFEAT 0xda2004  // Write : Feature
#define GCMD 0xda201c   // Write : Command
// Gayle IDE RW
#define GDATA 0xda2000     // Data
#define GSECTCNT 0xda2008  // SectorCount
#define GSECTNUM 0xda200c  // SectorNumber
#define GCYLLOW 0xda2010   // CylinderLow
#define GCYLHIGH 0xda2014  // CylinderHigh
#define GDEVHEAD 0xda2018  // Device/Head
#define GCTRL 0xda3018     // Control
// Gayle Ident
#define GIDENT 0xDE1000

// Gayle IRQ/CC
#define GCS 0xDA8000   // Card Control
#define GIRQ 0xDA9000  // IRQ
#define GINT 0xDAA000  // Int enable
#define GCONF 0xDAB00  // Gayle Config

/* DA8000 */
#define GAYLE_CS_IDE 0x80   /* IDE int status */
#define GAYLE_CS_CCDET 0x40 /* credit card detect */
#define GAYLE_CS_BVD1 0x20  /* battery voltage detect 1 */
#define GAYLE_CS_SC 0x20    /* credit card status change */
#define GAYLE_CS_BVD2 0x10  /* battery voltage detect 2 */
#define GAYLE_CS_DA 0x10    /* digital audio */
#define GAYLE_CS_WR 0x08    /* write enable (1 == enabled) */
#define GAYLE_CS_BSY 0x04   /* credit card busy */
#define GAYLE_CS_IRQ 0x04   /* interrupt request */
#define GAYLE_CS_DAEN 0x02  /* enable digital audio */
#define GAYLE_CS_DIS 0x01   /* disable PCMCIA slot */

/* DA9000 */
#define GAYLE_IRQ_IDE 0x80
#define GAYLE_IRQ_CCDET 0x40 /* credit card detect */
#define GAYLE_IRQ_BVD1 0x20  /* battery voltage detect 1 */
#define GAYLE_IRQ_SC 0x20    /* credit card status change */
#define GAYLE_IRQ_BVD2 0x10  /* battery voltage detect 2 */
#define GAYLE_IRQ_DA 0x10    /* digital audio */
#define GAYLE_IRQ_WR 0x08    /* write enable (1 == enabled) */
#define GAYLE_IRQ_BSY 0x04   /* credit card busy */
#define GAYLE_IRQ_IRQ 0x04   /* interrupt request */
#define GAYLE_IRQ_RESET 0x02 /* reset machine after CCDET change */
#define GAYLE_IRQ_BERR 0x01  /* generate bus error after CCDET change */

/* DAA000 */
#define GAYLE_INT_IDE 0x80     /* IDE interrupt enable */
#define GAYLE_INT_CCDET 0x40   /* credit card detect change enable */
#define GAYLE_INT_BVD1 0x20    /* battery voltage detect 1 change enable */
#define GAYLE_INT_SC 0x20      /* credit card status change enable */
#define GAYLE_INT_BVD2 0x10    /* battery voltage detect 2 change enable */
#define GAYLE_INT_DA 0x10      /* digital audio change enable */
#define GAYLE_INT_WR 0x08      /* write enable change enabled */
#define GAYLE_INT_BSY 0x04     /* credit card busy */
#define GAYLE_INT_IRQ 0x04     /* credit card interrupt request */
#define GAYLE_INT_BVD_LEV 0x02 /* BVD int level, 0=lev2,1=lev6 */
#define GAYLE_INT_BSY_LEV 0x01 /* BSY int level, 0=lev2,1=lev6 */

static int counter;
static uint8_t gayle_irq, gayle_int, gayle_cs, gayle_cs_mask, gayle_cfg;
static struct ide_controller *ide0;
static int fd;

unsigned int check_gayle_irq() {
  if (gayle_int & (1 << 7))
    return ide0->drive->intrq;

  return 0;
}

static void writeGayleB(unsigned int address, unsigned int value) {
  if (address == GFEAT) {
    ide_write8(ide0, ide_feature_w, value);
    return;
  }
  if (address == GCMD) {
    ide_write8(ide0, ide_command_w, value);
    return;
  }
  if (address == GSECTCNT) {
    ide_write8(ide0, ide_sec_count, value);
    return;
  }
  if (address == GSECTNUM) {
    ide_write8(ide0, ide_sec_num, value);
    return;
  }
  if (address == GCYLLOW) {
    ide_write8(ide0, ide_cyl_low, value);
    return;
  }
  if (address == GCYLHIGH) {
    ide_write8(ide0, ide_cyl_hi, value);
    return;
  }
  if (address == GDEVHEAD) {
    ide_write8(ide0, ide_dev_head, value);
    return;
  }
  if (address == GCTRL) {
    ide_write8(ide0, ide_devctrl_w, value);
    return;
  }

  if (address == GIDENT) {
    counter = 0;
    // printf("Write Byte to Gayle Ident 0x%06x (0x%06x)\n",address,value);
    return;
  }

  if (address == GIRQ) {
    //	 printf("Write Byte to Gayle GIRQ 0x%06x (0x%06x)\n",address,value);
    gayle_irq = (gayle_irq & value) | (value & (GAYLE_IRQ_RESET | GAYLE_IRQ_BERR));

    return;
  }

  if (address == GCS) {
    printf("Write Byte to Gayle GCS 0x%06x (0x%06x)\n", address, value);
    gayle_cs_mask = value & ~3;
    gayle_cs &= ~3;
    gayle_cs |= value & 3;
    return;
  }

  if (address == GINT) {
    printf("Write Byte to Gayle GINT 0x%06x (0x%06x)\n", address, value);
    gayle_int = value;
    return;
  }

  if (address == GCONF) {
    printf("Write Byte to Gayle GCONF 0x%06x (0x%06x)\n", address, value);
    gayle_cfg = value;
    return;
  }

  printf("Write Byte to Gayle Space 0x%06x (0x%06x)\n", address, value);
}

static void writeGayle(unsigned int address, unsigned int value) {
  if (address == GDATA) {
    ide_write16(ide0, ide_data, value);
    return;
  }

  printf("Write Word to Gayle Space 0x%06x (0x%06x)\n", address, value);
}

static void writeGayleL(unsigned int address, unsigned int value) {
  printf("Write Long to Gayle Space 0x%06x (0x%06x)\n", address, value);
}

static unsigned int readGayleB(unsigned int address) {
  if (address == GERROR) {
    return ide_read8(ide0, ide_error_r);
  }
  if (address == GSTATUS) {
    return ide_read8(ide0, ide_status_r);
  }

  if (address == GSECTCNT) {
    return ide_read8(ide0, ide_sec_count);
  }

  if (address == GSECTNUM) {
    return ide_read8(ide0, ide_sec_num);
  }

  if (address == GCYLLOW) {
    return ide_read8(ide0, ide_cyl_low);
  }

  if (address == GCYLHIGH) {
    return ide_read8(ide0, ide_cyl_hi);
  }

  if (address == GDEVHEAD) {
    return ide_read8(ide0, ide_dev_head);
  }

  if (address == GCTRL) {
    return ide_read8(ide0, ide_altst_r);
  }

  if (address == GIDENT) {
    uint8_t val;
    // printf("Read Byte from Gayle Ident 0x%06x (0x%06x)\n",address,counter);
    if (counter == 0 || counter == 1 || counter == 3) {
      val = 0x80;  // 80; to enable gayle
    } else {
      val = 0x00;
    }
    counter++;
    return val;
  }

  if (address == GIRQ) {
    //	printf("Read Byte From GIRQ Space 0x%06x\n",gayle_irq);

    return 0x80;  //gayle_irq;
                  /*
    uint8_t irq;
    irq = ide0->drive->intrq;

    if (irq == 1) {
      // printf("IDE IRQ: %x\n",irq);
      return 0x80;  // gayle_irq;
    }

    return 0;
*/
  }

  if (address == GCS) {
    printf("Read Byte From GCS Space 0x%06x\n", 0x1234);
    uint8_t v;
    v = gayle_cs_mask | gayle_cs;
    return v;
  }

  if (address == GINT) {
    //	printf("Read Byte From GINT Space 0x%06x\n",gayle_int);
    return gayle_int;
  }

  if (address == GCONF) {
    printf("Read Byte From GCONF Space 0x%06x\n", gayle_cfg & 0x0f);
    return gayle_cfg & 0x0f;
  }

  printf("Read Byte From Gayle Space 0x%06x\n", address);
  return 0xFF;
}

static unsigned int readGayle(unsigned int address) {
  if (address == GDATA) {
    uint16_t value;
    value = ide_read16(ide0, ide_data);
    //	value = (value << 8) | (value >> 8);
    return value;
  }

  printf("Read Word From Gayle Space 0x%06x\n", address);
  return 0x8000;
}

static unsigned int readGayleL(unsigned int address) {
  printf("Read Long From Gayle Space 0x%06x\n", address);
  return 0x8000;
}

int init_gayle() {
  ide0 = ide_allocate("cf");

  fd = open("hd0.img", O_RDWR);
  if (fd < 0) {
    printf("HDD Image hd0.image failed open\n");
    return -1;
  }

  ide_attach(ide0, 0, fd);
  ide_reset_begin(ide0);
  printf("HDD Image hd0.image attached\n");

  struct ps_device gayle_device = {
      readGayleB, readGayle, readGayleL,
      writeGayleB, writeGayle, writeGayleL};

  uint32_t devno = ps_add_device(&gayle_device);
  ps_add_range(devno, 0xd80000, 0x40000);
  ps_add_range(devno, 0xdd0000, 0x20000);
  return 0;
}
