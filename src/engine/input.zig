pub const InputState = struct {
    move_forward: bool = false,
    move_backward: bool = false,
    move_left: bool = false,
    move_right: bool = false,
    move_up: bool = false,
    move_down: bool = false,

    look_left: bool = false,
    look_right: bool = false,
    look_up: bool = false,
    look_down: bool = false,
    look_delta_x: f32 = 0.0,
    look_delta_y: f32 = 0.0,

    fast: bool = false,
    reset_camera: bool = false,
};
