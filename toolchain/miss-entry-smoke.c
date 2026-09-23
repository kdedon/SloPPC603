#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t miss_count;
volatile uint32_t miss_records[4][8];
extern uint32_t miss_load(uint32_t);
extern void miss_store(uint32_t, uint32_t);
extern char miss_load_pc[], miss_store_pc[];
#define WSPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)):"memory")
#define WSR(n,v) __asm__ volatile("mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)):"memory")
static int record(unsigned n, uint32_t ea, uint32_t cmp, uint32_t h1, uint32_t h2, uint32_t pc, uint32_t flags) {
  return miss_records[n][0]==ea && miss_records[n][1]==cmp &&
    miss_records[n][2]==h1 && miss_records[n][3]==h2 &&
    miss_records[n][4]==pc && (miss_records[n][5]&0x0fffffffu)==flags &&
    miss_records[n][6]==0x20040 && miss_records[n][7]==n+1;
}
int main(void) {
  uint32_t changed_way=*(volatile uint32_t *)0xfff0b000;
  if(changed_way>1) return 0x8d000009;
  __asm__ volatile("sync" ::: "memory");
  WSPR(25,0x00100000);
  WSPR(529,0xfff00002); WSPR(528,0xfff00002);
  WSPR(537,0xfff00002); WSPR(536,0xfff00002);
  WSR(1,0x1234); WSR(2,0x5678);
  /* A resident C=0 page exercises the store-change entry as well as misses. */
  WSPR(977,0x80091a00); WSPR(982,0xfff0a102); WSPR(27,changed_way<<17);
  uint32_t ea=0x1000a000;
  __asm__ volatile("tlbld %0; isync" :: "r"(ea):"memory");
  *(volatile uint32_t *)0xfff08000=0x13579bdf;
  uint32_t mode=0x70;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode):"memory");
  if (((uint32_t (*)(uint32_t))0x20000000)(25)!=42 || miss_count!=1) return 0x8d000001;
  if (miss_load(0x10008000)!=0x13579bdf || miss_count!=2) return 0x8d000002;
  miss_store(0x10009000,0x2468ace0);
  if (*(volatile uint32_t *)0xfff09000!=0x2468ace0 || miss_count!=3) return 0x8d000003;
  miss_store(0x1000a000,0xaabbccdd);
  if (*(volatile uint32_t *)0xfff0a000!=0xaabbccdd || miss_count!=4) return 0x8d000004;
  if (!record(0,0x20000000,0x802b3c00,0x00109e00,0x001061c0,0x20000000,0x40070)) return 0x8d000005;
  if (!record(1,0x10008000,0x80091a00,0x00108f00,0x001070c0,(uint32_t)miss_load_pc,0x70)) return 0x8d000006;
  if (!record(2,0x10009000,0x80091a00,0x00108f40,0x00107080,(uint32_t)miss_store_pc,0x10070)) return 0x8d000007;
  if (!record(3,0x1000a000,0x80091a00,0x00108f80,0x00107040,(uint32_t)miss_store_pc,0x10070|(changed_way<<17))) return 0x8d000008;
  return 1;
}
