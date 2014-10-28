;; bootsect.asm - simple bootloader for stboot
;; by trya - tryagainprod@gmail.com

%define mbr_address  0x7C00
%define code_address 0x2000

[ORG code_address] ; assuming we're working at the new location
[BITS 16]

%macro print_msg 1
  mov si, %1
  call write_msg
%endmacro

bootsect:
;; First things first, move this bootloader to another address
  cli
  mov sp, mbr_address
  cld
  mov si, sp
  mov di, code_address
  mov cx, 512/4
  rep movsd
  
  jmp far 0x0:main
  
main:
  sti
  
;; Welcome message
  print_msg msg1
  
;; Retrieve number of HDDs
  mov ax, 0x8
  mov dl, 0x80
  mov di, 0
  int 0x13
  mov [last_hdd], dl

read_mbr:  
  mov esi, 0
  call read_disk
  
;; Read the partition table
  mov bx, mbr_address+0x1BE
read_table:
  cmp bx, mbr_address+0x1FE
  jnb read_ebr ; no more primary partitions,
               ; let's take a look at logical partitions
  
  call copy_entry
  add bx, 0x10 ; move to the next partition table entry
  
;; Is the partition extended?
extended:
  mov al, [pt_type]
  cmp al, 0x05
  je is_extended
  cmp al, 0x0F
  jne active
is_extended:
  mov al, 1
  mov [ebr_exists], al
  mov eax, [pt_start]
  mov [ebr_start], eax

;; Is the partition active?
active:
  call is_active
  test al, al
  jz read_table
  
;; Copy the VBR of the selected partition and boot
goodbye:
  print_msg msg2          ; chainloading message
  mov esi, [pt_start]
  call read_disk
  jmp far 0x0:mbr_address

;; Probe the logical partitions
read_ebr:
  mov al, [ebr_exists]
  test al, al
  jz hdd_end
  mov eax, [ebr_start]
  mov [curr_ebr], eax
next_ebr:
  mov esi, [curr_ebr]
  call read_disk            ; copy the EBR
  mov bx, mbr_address+0x1BE
  call copy_entry           ; copy first entry
  add bx, 0x10
  call is_active
  test al, al
  jz not_active
;; Prepare booting
  mov eax, [curr_ebr]
  add eax, [pt_start]
  mov [pt_start], eax
  jmp goodbye
not_active:
  call copy_entry
  mov al, [pt_type]
  test al, al
  jz hdd_end
  mov eax, [ebr_start]
  add eax, [pt_start]
  mov [curr_ebr], eax
  jmp next_ebr
  
hdd_end:
  mov al, [curr_hdd]
  mov bl, [last_hdd]
  cmp al, bl
  je fail
  inc al
  mov [curr_hdd], al
  jmp read_mbr
  
fail:
  print_msg msg3
  jmp $
;; Main code ends here

;; Procedures
;; Method for loading first sector with modern BIOS extensions
read_disk:
  mov eax, esi          ; sector number
  mov [dap_sect], eax
  mov ax, mbr_address   ; destination address
  mov [dap_dest], ax
  mov ah, 0x42          ; read extended sectors
  mov dl, [curr_hdd]    ; current hard drive
;; We assume that the 'ds' register has been set to 0x0 by stboot
  mov si, dap
  int 0x13
  ret
  
;; Copy an entry from the partition table
copy_entry:
  cld
  mov si, bx
  mov di, pt_entry
  mov cx, 16/4
  rep movsd
  ret
  
;; Is the partition active?
is_active:
  mov al, [pt_active]
  cmp al, 0x80
  je true
  jmp false
true:
  mov al, 1
  ret
false:
  mov al, 0
  ret
  
;; Writes string from DS:SI until null character is met
write_msg:
  mov ah, 0xE ; write a TTY character
  xor bh, bh
  mov bl, 0x7 ; color attribute
.nextchar:
  lodsb
  or al, al
  jz .return
  int 0x10
  jmp .nextchar
.return:
  ret
;; End of procedures

;; Data
messages:
  msg1 db 'Welcome to the VBR loader!',10,13,0
  msg2 db 'Chainloading from partition...',10,13,0
  msg3 db 'No stboot partition. Aborting.',10,13,0
  
hdd_indexes:
  last_hdd db 0    ; index of the last HDD
  curr_hdd db 0x80 ; currently probed HDD
  
pt_entry:
  pt_active db 0
  times 3   db 0 ; CHS address, useless here
  pt_type   db 0
  times 3   db 0 ; same here
  pt_start  dd 0
  pt_size   dd 0
  
ebr:
  ebr_exists db 0
  ebr_start  dd 0
  curr_ebr   dd 0
  
;; Disk address packet, required by int 13h extensions
dap:
           db 16 ; size of DAP
           db 0  ; unused
           dw 1  ; number of sectors to be read
  dap_dest dw 0  ; offset of the destination
           dw 0  ; segment of the destination
  dap_sect dd 0  ; low 4 bytes of the first sector to read
           dd 0  ; high 4 bytes
  
;; Pad to the 446-bytes code limit, just before the partition table
  times 446-($-$$) db 0
  
pt_table:
  first:  times 16 db 0
  second: times 16 db 0
  third:  times 16 db 0
  fourth: times 16 db 0
pt_table_end:
  dw 0xAA55
bootsect_end:
;; End of data
