#ifndef _PS_CUSTOMCHIPS_H
#define _PS_CUSTOMCHIPS_H

#define INTENAR 0xdff01c
#define INTREQR 0xdff01e
#define INTENA 0xdff09a
#define INTREQ 0xdff09c

#define INTF_SETCLR 0x8000
#define INTF_INTEN 0x4000
#define INTF_PORTS 0x0008

int init_customchips();

#endif /* _PS_CUSTOMCHIPS_H */
