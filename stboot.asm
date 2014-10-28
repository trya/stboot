;; stboot.asm
;; by trya - tryagainprod@gmail.com

;; CEFULL is loaded at 0x100000 in 32-bit protected mode, hence...
[ORG 0x100000]
[BITS 32]

%define cefull_size    (cefull_end-cefull)
%define stage2_size    (stage2_end-stage2)
%define mbr_size       (mbr_end-mbr)
%define gdt_size       (gdt_end-gdt-1)

%define mbr_address    0x7C00
%define stage2_address 0x1000
%define rm_address(x)  (stage2_address+(x-stage2))

%macro print_msg 1
  mov si, %1
  call write_msg
%endmacro

cefull:
header:
;; Reproducing the CE header (0xc0 length)
  jmp short header+0x40 ; EB3E
  db 0x45,0x54
  dd cefull_size        ; executable size (checked by DeviceVM rom loader)
  times 0x38 db 0
  jmp short header+0xC0 ; EB7E
  db 0x43,0x45
  times 0x7C db 0
header_end:

stage1:
;; Our code starts here
;; NB: I let the stack setup to the chainloaded bootsector
  cli

;; Load our GDT
  lgdt [stage1_gdtr]

;; Jump to our 32-bit code segment
  jmp far 0x8:pm_code

pm_code:
;; Assign the new 32-bit data segment selector to the other segment registers
  mov eax, 0x10
  mov ds, eax
  mov ss, eax
  mov es, eax
  mov fs, eax
  mov gs, eax

;; Copy the included boot sector to 0x7c00
  cld
  mov esi, mbr
  mov edi, mbr_address
  mov ecx, mbr_size/4     ; double-word blocks for faster copy
  rep movsd

;; Copy the 2nd stage code and data to 0x1000
  mov esi, stage2
  mov edi, stage2_address
  mov ecx, stage2_size/4  ; double-word blocks
  rep movsd

;; Load the GDT from real mode address space
  lgdt [rm_address(stage2_gdtr)]

;; Jump to our new code in 16-bit protected mode (16-bit GDT code selector)
  jmp far 0x18:stage2_address
stage1_end:

[BITS 16]

stage2:
;; Disable protected mode by clearing its flag in CR0
  mov eax, cr0
  and al, 11111110b
  mov cr0, eax

;; Reinitialize the other segment registers with a real mode compatible value
  mov ax, 0x0
  mov ds, ax
  mov ss, ax
  mov es, ax
  mov fs, ax
  mov gs, ax

;; Disable A20, assuming it was enabled by the rom loader
  in  al, 0x92
  and al, 11111101b
  out 0x92, al

;; Load real mode IDT
  lidt [rm_address(idtr)]

;; Jump to real mode code address
  jmp far 0x0:rm_address(rm_code)

rm_code:
;; Back into serious business, enable interrupts
  sti

;; Set video mode
  mov ah, 0x00
  mov al, 0x03 ; 80x25 text mode (16 colors)
  int 0x10
  
;; Welcome message
  print_msg rm_address(msg1)
  print_msg rm_address(msg2)

;; We're in real mode and the CPU is in a sane state,
;; so we let the boot sector take control
  jmp far 0x0:0x7C00

;; Main code ends here

;; Writes string from DS:SI until null character is met
write_msg:
  mov ah, 0xE
  xor bh, bh
  mov bl, 0x7
.nextchar:
  lodsb
  or al,al
  jz .return
  int 0x10
  jmp .nextchar
.return:
  ret

messages:
  msg1 db 'stboot has escaped from protected mode!',10,13,0
  msg2 db 'Now passing control to the boot sector...',10,13,0

;; GDT: table of 64-bit entries, first element of the table is NULL
;; Usual descriptor structure (rather complicated):
;; |___db___|___db___|___db___|___db___|___db___|___db___|____db_____|___db___|
;; |0______________15|16______________________39|40____47|48_51|52_55|56____63|
;; |      Limit      |                          |        |Limit|     |  Base  |
;; |      first      |    Base first 24 bits    | Flags  |last |Flags|  last  |
;; |_____16 bits_____|__________________________|________|4bits|_____|_8_bits_|

;; The only differences between 32 and 16-bit entries
;; are the granularity and the 16/32-bit flags

gdt:
  db 0,0,0,0,0,0,0,0
gdt_pm_cs:
  db 0xFF,0xFF,0x0,0x0,0x0,10011010b,11001111b,0x0
gdt_pm_ds:
  db 0xFF,0xFF,0x0,0x0,0x0,10010010b,11001111b,0x0
gdt_rm_cs:
  db 0xFF,0xFF,0x0,0x0,0x0,10011010b,00000000b,0x0
gdt_end:

;; GDT register: 48-bit (16+32) register
;; |_____dw_____|__________dd__________|
;; |0_________15|16__________________47|
;; |            |                      |
;; |  GDT size  |     GDT pointer      |
;; |____________|______________________|

stage1_gdtr:
  dw gdt_size
  dd gdt

stage2_gdtr:
  dw gdt_size
  dd rm_address(gdt)

;; IDT register: same structure as GDTR

idtr:
  dw 0x3FF ; 256 entries
  dd 0     ; real mode IVT at 0x0
stage2_end:

;; Included boot sector, to be copied to 0x7c00
mbr:
  INCBIN "bootsect.bin"
mbr_end:
cefull_end:
