#include "mod_runtime.h"
#include "runtime_arm.h"

namespace {

constexpr uint32_t kAffineBufferSelectorImmediatePc = 0x08030C14u;

RuntimeThumbAluImmediateOverride previous_override = nullptr;
bool installed = false;

int override_affine_buffer_selector(uint32_t instruction_pc,
                                    uint32_t original_value,
                                    uint32_t* out_value) {
    if (instruction_pc == kAffineBufferSelectorImmediatePc &&
        original_value == 1u && out_value) {
        // The following guest SUBS becomes selector - selector, keeping the
        // HDMA-visible output buffer selected and freshly generated each frame.
        *out_value = g_cpu.R[1];
        return 1;
    }
    return previous_override
        ? previous_override(instruction_pc, original_value, out_value)
        : 0;
}

void reset_track_60fps() {
    if (!installed) return;
    if (g_runtime_thumb_alu_imm_override ==
        override_affine_buffer_selector) {
        g_runtime_thumb_alu_imm_override = previous_override;
    }
    previous_override = nullptr;
    installed = false;
}

void activate_track_60fps() {
    if (installed) return;
    previous_override = g_runtime_thumb_alu_imm_override;
    g_runtime_thumb_alu_imm_override = override_affine_buffer_selector;
    installed = true;
}

}  // namespace

GBA_MOD_CONSTRUCTOR(mksc_register_track_60fps_plugin) {
    (void)gba_mod_register_reset_callback(reset_track_60fps);
    (void)gba_mod_register_activation_plugin(
        "mario-kart-super-circuit.track-60fps", activate_track_60fps);
}
