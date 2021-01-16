#ifndef _PS_IRQ_H
#define _PS_IRQ_H

#ifdef __cplusplus
extern "C" {
#endif

struct ps_irq_device {
  unsigned int (*check_irq)();
};

unsigned int read_intenar();
unsigned int read_intreqr();
void write_intena(unsigned int value);

void ps_add_int2_device(struct ps_irq_device *device);

void ps_set_irq();

#ifdef __cplusplus
}
#endif

#endif /* _PS_IRQ_H */
