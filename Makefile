FNAME=6

.PHONY: all
all: build

.PHONY: build
build:
	nasm -f bin -o bin/$(FNAME).bin src/$(FNAME).asm
	python3 -c 'f=open("bin/6.bin","rb"); top=f.read(); f.close(); f=open("bin/6.bin","ab"); f.write(bytes(reversed(top))); f.close()'
	xxd bin/$(FNAME).bin
	chmod +x bin/$(FNAME).bin

.PHONY:elf
elf: build
	qemu-riscv32 -strace bin/$(FNAME).bin

.PHONY:dicom
dicom: build
	dcm2img --accept-acr-nema bin/$(FNAME).bin bin/$(FNAME).png
	feh -Z --zoom 600 bin/$(FNAME).png

.PHONY:clean
clean:
	rm -f bin/*
