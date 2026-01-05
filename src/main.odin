package chip8


main :: proc() {
	vm, _ := vm_create()
	defer vm_destroy(&vm)

	vm_run(&vm)
}
