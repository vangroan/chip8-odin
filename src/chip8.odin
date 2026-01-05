package chip8

import "base:runtime"
import "core:mem"


// Number of general purpose 8-bit registers.
REGISTER_COUNT :: 16

// Total size of CHIP-8 RAM.
MEMORY_SIZE :: 0x1000
MEMORY_MASK :: MEMORY_SIZE - 1

// Levels of nesting allowed in the call stack.
//
// The original RCA 1802 implementation allocated 48 bytes
// for up to 12 levels of nesting.
//
// There is no practical reason to have this limitation anymore.
// Increasing it does not affect the correctness of programs.
//
// Keeping it a power-of-two allows for efficiently masking
// the stack pointer.
STACK_SIZE :: 0x10

// Memory address where programs start.
MEMORY_START :: 0x200

DISPLAY_WIDTH  :: 64
DISPLAY_HEIGHT :: 32

// Number of bytes the instruction pointer is advanced
// during ojne machine step.
STEP_OFFSET :: 2

// Address to a location in CHIP-8 RAM.
Address :: u16


// The CHIP-8 CPU represents the state of the virtual machine.
Chip8_CPU :: struct {
	// Instruction pointer to the current position in the bytecode.
	ip : int,
	// Stack pointer to the top of the return pointer stack.
	sp : int,
	// General purpose registers for temporary values.
	//
	// Register 16 (VF) is used for either the carry flag,
	// or borrow switch depending on opcode.
	reg : [REGISTER_COUNT]u8,
	// Pointer register used for temporarily storing an address
	// Since addresses are 12 bits, only the lowest (rightmost) bits are used.
	address : Address,
	// (DT) Delay timer that counts down to 0.
	delay_timer : u8,
	// (ST) Sound timer that counts down to 0.
	// When it has a non-zero value, a beep is played.
	sound_timer : u8,
	// Main machine RAM.
	ram : ^[MEMORY_SIZE]u8,
	// Stack of return pointers used for jumping when a routine call finishes.
	stack : [STACK_SIZE]Address,
	// Screen buffer that is drawn too.
	display : ^[DISPLAY_HEIGHT]u64,
}


chip8_init :: proc(cpu: ^Chip8_CPU, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
	cpu.ip      = MEMORY_START
	cpu.ram     = new([MEMORY_SIZE]u8, allocator) or_return
	cpu.display = new([DISPLAY_HEIGHT]u64, allocator) or_return
	return nil
}


chip8_destroy :: proc(cpu: ^Chip8_CPU) {
	free(cpu.ram)
	free(cpu.display)
}


chip8_next_op :: proc(cpu: ^Chip8_CPU) -> (a: u8, b: u8) {
	a = cpu.ram[cpu.ip & MEMORY_MASK]
	b = cpu.ram[(cpu.ip + 1) & MEMORY_MASK]
	return
}

@(private)
advance_ip :: #force_inline proc(cpu: ^Chip8_CPU) {
	cpu.ip = (cpu.ip + STEP_OFFSET) & MEMORY_MASK
}
