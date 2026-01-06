package chip8

import "base:runtime"
import "core:math/rand"


// Default number of instruction to evaluate per frame.
DEFAULT_IPF :: 15


Chip8_VM :: struct {
	cpu   : Chip8_CPU,
	error : Chip8_Error,
	ipf   : int,  // Instructions per second
}


Chip8_Flow :: enum {
	// Machine finished with no error.
	Ok,

	// Machine has encountered an error.
	Error,

	// Machine has jumped the instruction pointer
	// to a new position.
	//
	// This can be used to avoid getting stuck in
	// an infinite loop.
	Jump,

	// Wait for a keypress.
	//
	// This is triggered by the opcode `Fx0A` (`LD Vx, K`), which stops
	// execution until a key is pressed, and loads the key value into `Vx`.
	KeyWait,
}


Chip8_Error :: enum {
	None,
	StackOverflow,
}

vm_create :: proc(allocator := context.allocator) -> (vm: Chip8_VM, err: runtime.Allocator_Error) {
	vm = Chip8_VM {}
	chip8_init(&vm.cpu, allocator) or_return
	vm.ipf = DEFAULT_IPF
	rand.reset(987654321)
	return
}

vm_destroy :: proc(vm: ^Chip8_VM) {
	chip8_destroy(&vm.cpu)
}


vm_run :: proc(vm: ^Chip8_VM) -> (flow: Chip8_Flow) {
	flow    = .Ok
	frames := vm.ipf

	for f := 0; f < frames; f += 1 {
		flow = vm_step(vm)

		if flow != .Ok {
			break
		}
	}

	return flow
}


// Performs a single evaluation step.
vm_step :: proc(vm: ^Chip8_VM) -> (flow: Chip8_Flow) {
	flow = .Ok 

	a, b := chip8_next_op(&vm.cpu)
	op   := a >> 4   // 0xF000
	vx   := a & 0x0F // 0x0F00
	vy   := b >> 4   // 0x00F0
	n    := b & 0x0F // 0x000F
	nn   := b        // 0x00FF
	nnn  := (u16(vx) << 8) | u16(nn) // 0x0FFF

	advance_ip(&vm.cpu)

	switch op {
	// 1nnn (JP addr)
	//
	// Unconditionally jump to address.
	case 0x1:
		target := int(nnn) & MEMORY_MASK
		if target <= vm.cpu.ip {
			flow = .Jump
		}
		vm.cpu.ip = target
	// 2nnn (CALL addr)
	//
	// Call subroutine at NNN.
	case 0x2:
		vm.cpu.sp += 1
		if vm.cpu.sp >= STACK_SIZE {
			vm.error = .StackOverflow
			flow = .Error
		} else {
			// Save current instruction pointer
			// as the return address.
			vm.cpu.stack[vm.cpu.sp] = u16(vm.cpu.ip)
			vm.cpu.ip = int(nnn)
		}
	// 3xnn (SE Vx, byte)
	//
	// Skip the next instruction if register VX equals value NN.
	case 0x3:
		if vm.cpu.reg[vx] == nn {
			advance_ip(&vm.cpu)
		}
	// 4xnn (SNE Vx, byte)
	//
	// Skip the next instruction if register VX does not equal value NN.
	case 0x4:
		if vm.cpu.reg[vx] != nn {
			advance_ip(&vm.cpu)
		}
	// 5xy0 (SE Vx, Vy)
	//
	// Skip the next instruction if register VX equals value VY.
	case 0x5:
		if vm.cpu.reg[vx] == vm.cpu.reg[vy] {
			advance_ip(&vm.cpu)
		}
	// 6xnn (LD Vx, byte)
	//
	// Set register VX to value NN.
	case 0x6:
		vm.cpu.reg[vx] = nn
	// 7xnn (ADD Vx, byte)
	//
	// Add value NN to register VX. Carry flag is not set.
	case 0x7:
		vm.cpu.reg[vx] += nn
	// Annn (LD I, addr)
	//
	// Set address register I to value NNN.
	case 0xA:
		vm.cpu.address = nnn
	// Bnnn (JP V0, addr)
	//
	// Jump to location nnn + V0.
	case 0xB:
		target := (int(nnn) + int(vm.cpu.reg[0])) & MEMORY_MASK
		if target <= vm.cpu.ip {
			flow = .Jump
		}
		vm.cpu.ip = target
	// CXNN (RND Vx, byte)
	//
	// Generate random number.
	// Set register VX to the result of bitwise AND between a random number and NN.
	case 0xC:
		vm.cpu.reg[vx] = u8(rand.uint_range(0, 256)) & nn
	// Dxyn (DRW Vx, Vy, nibble)
	//
	// Draw sprite to the display buffer, at coordinate as per registers Vx and Vy.
	// Sprite is encoded as 8 pixels wide, N pixels high, stored in bits located in
	// memory pointed to by address register I.
	//
	// If the sprite is drawn outside the display area, it is wrapped around to the other side.
	//
	// If the drawing operation erases existing pixels in the display buffer, register VF is set to
	// 1, and set to 0 if no display bits are unset. This is used for collision detection.
	case 0xD:
		// Cast to unsigned for bitwise operations.
		x := uint(vm.cpu.reg[vx])
		y := uint(vm.cpu.reg[vy])
		sprite_w    :: uint(SPRITE_WIDTH)
		sprite_h    := uint(n)
		sprite_addr := uint(vm.cpu.address) & MEMORY_MASK
		is_erased := false
		BIT :: 1

		// Iteration from pointer in address register I to number of rows
		// specified by opcode value N.
		for r in 0..<sprite_h {
			dy := (y + r) & DISPLAY_H_MASK
			drow := vm.cpu.display[dy]
			srow := vm.cpu.ram[(sprite_addr + r) & MEMORY_MASK]

			dx1 := x & DISPLAY_W_MASK

			if dx1 >= DISPLAY_WIDTH - SPRITE_WIDTH {
				// Wrap to other side of screen.
				dx1 = dx1 >> DISPLAY_WRAP_BITS
			}
		}
	}

	return flow
}
