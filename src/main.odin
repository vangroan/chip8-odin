package chip8

import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import mu "vendor:microui"
import SDL "vendor:sdl3"


WINDOW_TITLE :: "CHIP-8"


Options :: struct {
	file : os.Handle `args:"pos=0,required,file=r" usage:"ROM file"`,
}


main :: proc() {
	// Tracking Allocator
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			for _, leak in track.allocation_map {
				fmt.eprintf("%v leaked %m\n", leak.location, leak.size)
			}
		}
	}

	// Setup Logging
	context.logger = log.create_console_logger()
	defer {
		log.destroy_console_logger(context.logger)
		context.logger = log.Logger{}
	}

	opt   : Options
	style : flags.Parsing_Style = .Odin

	flags.parse_or_exit(&opt, os.args, style)

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
	ui := new(mu.Context)
	defer free(ui)

	mu.init(ui)

	ui.text_width  = mu.default_atlas_text_width
	ui.text_height = mu.default_atlas_text_height

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
			case .MOUSE_MOTION:
				mu.input_mouse_move(ui, i32(event.motion.x), i32(event.motion.y))
			case .MOUSE_BUTTON_UP, .MOUSE_BUTTON_DOWN:
				if mu_btn := mouse_button_sdl_to_microui(event.button.button); mu_btn != nil {
					mu_btn_fn := mu.input_mouse_down if event.button.down else mu.input_mouse_up
					mu_btn_fn(ui, i32(event.button.x), i32(event.button.y), mu_btn)
				}
			case .KEY_UP, .KEY_DOWN:
				if event.key.key == SDL.K_ESCAPE {
					running = false
				}

				if mu_key, ok := key_sdl_to_microui(event.key.key); ok {
					mu_key_fn := mu.input_key_down if event.key.down else mu.input_key_up
					mu_key_fn(ui, mu_key)
				}
			}
		}

		vm_run(&vm)

		viewport_rect := mu.Rect{}
		SDL.GetRenderOutputSize(renderer, &viewport_rect.w, &viewport_rect.h)
		gui_windows(ui, &viewport_rect)

		SDL.SetRenderDrawColor(renderer, 20, 20, 30, 255)
		SDL.RenderClear(renderer)

		gui_render(ui, renderer)

		SDL.RenderPresent(renderer)

		free_all(context.temp_allocator)
	}
}


@private
gui_windows :: proc(ctx: ^mu.Context, viewport: ^mu.Rect) {
	mu.begin(ctx)
	if mu.window(ctx, "Foobar", mu.Rect{10, 10, 70, viewport.h - 20}) {
	}
	mu.end(ctx)
}

@private
gui_render :: proc(ctx: ^mu.Context, renderer: ^SDL.Renderer) {

	command_backing : ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		#partial switch cmd in variant {
		case ^mu.Command_Text:
			pos := fpoint_microui_to_sdl(cmd.pos)
			str := strings.clone_to_cstring(cmd.str, context.temp_allocator)
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)\
			SDL.RenderDebugText(renderer, pos.x, pos.y, str)
		case ^mu.Command_Rect:
			rect := rect_microui_to_sdl(&cmd.rect)
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			SDL.RenderFillRect(renderer, &rect)
		case ^mu.Command_Icon:
			rect := rect_microui_to_sdl(&cmd.rect)
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			SDL.RenderFillRect(renderer, &rect)
		}
	}
}

@private rect_microui_to_sdl :: #force_inline proc(rect: ^mu.Rect) -> SDL.FRect {
	return SDL.FRect{ f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h) }
}

@private fpoint_microui_to_sdl :: #force_inline proc(point: mu.Vec2) -> SDL.FPoint {
	return { f32(point.x), f32(point.y) }
}

@private
key_sdl_to_microui :: #force_inline proc(key: SDL.Keycode) -> (out: mu.Key, ok: bool) {
	ok = true

	switch key {
	case SDL.K_LSHIFT, SDL.K_RSHIFT: out = .SHIFT
	case SDL.K_LCTRL, SDL.K_RCTRL:   out = .CTRL
	case SDL.K_LALT, SDL.K_RALT:     out = .ALT
	case SDL.K_BACKSPACE: out = .BACKSPACE
	case SDL.K_DELETE:    out = .DELETE
	case SDL.K_RETURN:    out = .RETURN
	case SDL.K_LEFT:      out = .LEFT
	case SDL.K_RIGHT:     out = .RIGHT
	case SDL.K_HOME:      out = .HOME
	case SDL.K_END:       out = .END
	case SDL.K_A:         out = .A
	case SDL.K_X:         out = .X
	case SDL.K_C:         out = .C
	case SDL.K_V:         out = .V
	case: ok = false
	}

	return out, ok
}

@private
mouse_button_sdl_to_microui :: #force_inline proc(button: u8) -> mu.Mouse {
	// microui does not care about mouse side-buttons

	switch button {
	case SDL.BUTTON_LEFT:   return .LEFT
	case SDL.BUTTON_RIGHT:  return .RIGHT
	case SDL.BUTTON_MIDDLE: return .MIDDLE
	case: return nil
	}
}
