; Polydrome
; Author: xcel (https://github.com/xcellerator/polydrome)

; Description: A palidromic ELF/DICOM polyglot for BGGP6.

; To build:
;   nasm -f bin -o bin/6.bin src/6.asm
;   python3 -c 'f=open("bin/6.bin","rb"); top=f.read(); f.close(); f=open("bin/6.bin","ab"); f.write(bytes(reversed(top))); f.close()'
;   xxd +x bin/6.bin

; To test:
;   (ELF):   qemu-riscv32 -strace bin/6.bin
;   (DICOM): dcm2img --accept-acr-nema bin/6.bin bin/6.png && feh -Z --zoom 600 bin/6.png
;
;   Requires packages 'qemu-user', 'dcmtk' and 'feh' on Debian.

; The load address for the RV32 ELF.
%define LOAD_ADDR 0x00010000

; Padding values. 0xff ensures that these bytes will appear white in the DICOM image.
%define PAD1 0xff
%define PAD2 0xffff
%define PAD4 0xffffffff

; ELF Header (Elf32_Ehdr.e_ident)
EHDR_START:
db 0x7f, 'E', 'L', 'F'      ; EI_MAG0, EI_MAG1, EI_MAG2, EI_MAG3
db 0x01                     ; EI_CLASS = ELFCLASS32
db 0x01                     ; EI_DATA = ELFDATA2LSB
db 0x01                     ; EI_VERSION = 1
db PAD1                     ; EI_OSABI, Not checked.
times 8 db PAD1             ; EI_PAD

; ELF Header (Elf32_Ehdr.e_type ...)
dw 0x0002                   ; e_type = ET_EXEC
dw 0x00f3                   ; e_machine = EM_RISCV
dd PAD4                     ; e_version, Not checked.
dd CODE_START+LOAD_ADDR+4   ; e_entry, +4 to skip over the invalid reversed `ecall` instruction.
dd PHDR_START               ; e_phoff = Offset to program header.
dd PAD4                     ; e_shoff, Not checked.
dd 0x00000000               ; e_flags
dw 0x0034                   ; e_ehsize = sizeof(Elf32_Ehdr)
dw 0x0020                   ; e_phensize = sizeof(Elf32_Phdr)
dw 0x0001                   ; e_phnum
dw PAD2                     ; e_shentsize
dw PAD2                     ; e_shnum
dw PAD2                     ; e_shstrndx

; ELF Program Header (Elf32_Phdr)
PHDR_START:
dd 0x00000001               ; p_type = PT_LOAD
dd 0x00000000               ; p_offset
dd LOAD_ADDR                ; p_vaddr
dd PAD4                     ; p_paddr, Not checked.
dd (CODE_END-CODE_START)*2  ; p_filesz
dd (CODE_END-CODE_START)*2  ; p_memsz
dd 0x00000005               ; p_flags = PF_R | PF_X
dd PAD4                     ; p_align, Not checked.
PHDR_END:

; DICOM Pixel Data.
; The DICOM image's aspect ratio is 40x40 bits = 5x5 bytes. We begin 3 bytes away from the right-egde, so adding 8
; bytes of 0xff takes us to the start of a new row with a whole row of white pixels above us. Then we have the pixel
; data itself which are bitmapped, big-endian bytes in REVERSE order because these bytes will be reflected into the
; second half of the binary, which is where they will be rendered from. Lastly, we have to pad the binary to offset
; 0x80, which is where the DICOM header must begin.
times 8 db 0xff             ; Padding to align 'BGGP6' art in 40x40 aspect ratio.
db 0xc3, 0xfb, 0xc3, 0xc3, 0xc3, 0xdb, 0xfb, 0xdb, 0xdb, 0xdb, 0xc3, 0xc3, 0xcb, 0xcb, 0xe3, 0xfb, 0xdb, 0xfb, 0xfb, 0xdb, 0xc3, 0xc3, 0xc3, 0xc3, 0xc3
times 0x80-($-$$) db 0xff   ; Padding for DICOM header alignment.

DICOM_START:
db 'D', 'I', 'C', 'M'       ; DICOM header

; Required DICOM TLVs: Rows, Columns, BitsAllocated, BitsStored, PixelRepresentation and PixelData.
dd 0x00100028               ; Tag = Rows
dd 0x00000002               ; Length = 2
dw 0x0028                   ; Value = 40

dd 0x00110028               ; Tag = Columns
dd 0x00000002               ; Length = 2
dw 0x0028                   ; Value = 40

dd 0x01000028               ; Tag = BitsAllocated
dd 0x00000002               ; Length = 2
dw 0x0001                   ; Value = 1

dd 0x01010028               ; Tag = BitsStored
dd 0x00000002               ; Length = 2
dw 0x0001                   ; Value = 1

dd 0x01030028               ; Tag = PixelRepresentation
dd 0x00000002               ; Length = 2
dw 0x0000                   ; Value = 1

dd 0x00107fe0               ; Tag = PixelData
dd 0x0000011a               ; Length (to EOF)
DICOM_END:

; The RV32 instructions that will be executed when this binary is treated as an ELF.
; The only irreversible instruction we have to use is `ecall`. This is why we have to add `4` to the value of e_entry
; in the ELF header in order to skip over this invalid instruction.

; Following that, all the instructions are reversible and execute as follows:
;
; (1) Six `c.addi a0, 1` instructions which will put the value `6` into register `A0`.
; (2) Eleven `c.addi a1, 0x1f` instructions, followed by a single `c.addi a1, 0x18` instruction, which will put the
;     value `0x16d = 365` into register `A1`.
; (3) A single `c.addi s3, 3` instruction, which is irrelevant to our program execution.
; (4) A single `xori a7, a1, 0x130` instruction. This will take the value in `A1` (`0x16d`), XOR it with `0x130` to
;     produce `0x5d` and store it in register `A7`. This value corresponds to RV32 Linux syscall EXIT and `A7` is the
;     register that the syscall must be placed in before executing `ecall`.
; (5) This is the half-way mark, now we revisit the instructions we've already executed but in byte-reversed order.
; (6) A single `c.sub a0, a0` which will set register `A0` to the value `0`.
; (7) A single `c.bnez a0, 0x20` instruction, followed by eleven `c.bnez a0, -0xc8`. None of these instructions will
;     result in jumping anywhere because `A0` is `0`.
; (8) Six `c.addi a0, 1` instructions which will place the value `6` into register `A0`.
; (9) A single `ecall` instruction which will trigger syscall `0x5d` (EXIT) with value `6`.

CODE_START:
db 0x00, 0x00, 0x00, 0x73   ; Invalid, reverses to `ecall`

db 0x05, 0x05               ; `c.addi a0, 1`
db 0x05, 0x05               ; `c.addi a0, 1`
db 0x05, 0x05               ; `c.addi a0, 1`
db 0x05, 0x05               ; `c.addi a0, 1`
db 0x05, 0x05               ; `c.addi a0, 1`
db 0x05, 0x05               ; `c.addi a0, 1`

db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xfd, 0x05               ; `c.addi a1, 0x1f`, reverses to `c.bnez a0, -0xc8`
db 0xe1, 0x05               ; `c.addi a1, 0x18`, reverses to `c.bnez a0, 0x20`

db 0x8d, 0x09               ; `c.addi s3, 3`, reverses to `c.sub a0, a0`

db 0x93, 0xc8, 0x05, 0x13   ; `xori a7, a1, 0x130`, reverses to `addi a0, a6, -0x6c4`

CODE_END:
