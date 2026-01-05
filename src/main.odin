package chip8

import "core:fmt"
import "core:log"
import "core:mem"
import "vendor:microui"
import SDL "vendor:sdl3"


WINDOW_TITLE :: "CHIP-8"


main :: proc() {
	// Tracking Allocator
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			for _, leak in track.allocation_map {
				fmt.printf("%v leaked %m\n", leak.location, leak.size)
			}
		}
	}

	// Setup Logging
	context.logger = log.create_console_logger()
	defer {
		log.destroy_console_logger(context.logger)
		context.logger = log.Logger{}
	}

	main_gui()
}


main_gui :: proc() {

	// ---------------------------------------------------------------------- //
	// Setup SDL3
	if ok := SDL.Init({.AUDIO, .VIDEO}); !ok {
		log.errorf("Failed to initialise SDL3: %s", SDL.GetError())
	}
	defer SDL.Quit()

	window := SDL.CreateWindow(WINDOW_TITLE, 800, 400, {.RESIZABLE})
	if window == nil {
		log.errorf("Failed to create window: %s", SDL.GetError())
		return
	}
	defer SDL.DestroyWindow(window)

	renderer := SDL.CreateRenderer(window, nil)
	if renderer == nil {
		log.errorf("Failed to create renderer: %s", SDL.GetError())
		return
	}
	defer SDL.DestroyRenderer(renderer)

	// ---------------------------------------------------------------------- //
	// Setup microui
	ui := new(microui.Context)
	defer free(ui)

	microui.init(ui)

	ui.text_width  = microui.default_atlas_text_width
	ui.text_height = microui.default_atlas_text_height

	// ---------------------------------------------------------------------- //
	// Setup CHIP-8
	vm, err := vm_create()
	if err != .None {
		log.errorf("Failed to allocate VM internals: %v", err)
	}
	defer vm_destroy(&vm)

	// ---------------------------------------------------------------------- //
	// Main Loop
	event   := SDL.Event{}
	running := true

	for running {
		for SDL.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_UP, .KEY_DOWN:
				if event.key.key == SDL.K_ESCAPE {
					running = false
				}
			}
		}

		vm_run(&vm)

		gui_windows(ui)

		SDL.SetRenderDrawColor(renderer, 20, 20, 30, 255)
		SDL.RenderClear(renderer)

		gui_render(ui, renderer)

		SDL.RenderPresent(renderer)
	}
}


@private
gui_windows :: proc(ctx: ^microui.Context) {
	microui.begin(ctx)
	if microui.window(ctx, "Foobar", microui.Rect{10, 10, 100, 200}) {

	}
	microui.end(ctx)
}

@private
gui_render :: proc(ctx: ^microui.Context, renderer: ^SDL.Renderer) {

	command_backing : ^microui.Command
	for variant in microui.next_command_iterator(ctx, &command_backing) {
		#partial switch cmd in variant {
		case ^microui.Command_Text:
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
		case ^microui.Command_Rect:
			rect := rect_microui_to_sdl(&cmd.rect)
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			SDL.RenderFillRect(renderer, &rect)
		}
	}
}

@private rect_microui_to_sdl :: #force_inline proc(rect: ^microui.Rect) -> SDL.FRect {
	return SDL.FRect{ f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h) }
}
