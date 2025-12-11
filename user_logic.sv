`timescale 1ns/1ps
`default_nettype none

module user_logic (
    input wire tck,
    input wire tdi,
    output logic tdo,
    input wire test_logic_reset,
    input wire run_test_idle,
    input wire ir_is_user,
    input wire capture_dr,
    input wire shift_dr,
    input wire update_dr
);

logic inbound_valid;
/* verilator lint_off UNUSEDSIGNAL */
byte inbound_data;
/* verilator lint_on UNUSEDSIGNAL */

tap_decoder #(
    .DATA_WIDTH($bits(inbound_data))
) tap_decoder_i (
    // TAP signals
        .tck(tck),
        .tdi(tdi),
        .ir_is_user(ir_is_user),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
    // Decoded signals
        .valid(inbound_valid),
        .data(inbound_data)
);

localparam int COUNTER_WIDTH = 28;
typedef logic [COUNTER_WIDTH-1:0] count_t;
count_t tck_cycle_count_any_state = '0;
count_t tck_cycle_count_test_logic_reset_state = '0;
count_t tck_cycle_count_run_test_idle_state = '0;
count_t tck_cycle_count_ir_is_user_state = '0;
count_t tck_cycle_count_capture_dr_state = '0;
count_t tck_cycle_count_shift_dr_state = '0;
count_t tck_cycle_count_update_dr_state = '0;
localparam count_t STATIC_DATA = 28'hCAFEDEC;

always_ff @(posedge tck) tck_cycle_count_any_state <= tck_cycle_count_any_state + 1;
always_ff @(posedge tck) tck_cycle_count_test_logic_reset_state <= (test_logic_reset) ? tck_cycle_count_test_logic_reset_state + 1 : tck_cycle_count_test_logic_reset_state;
always_ff @(posedge tck) tck_cycle_count_run_test_idle_state <= (run_test_idle) ? tck_cycle_count_run_test_idle_state + 1 : tck_cycle_count_run_test_idle_state;
always_ff @(posedge tck) tck_cycle_count_ir_is_user_state <= (ir_is_user) ? tck_cycle_count_ir_is_user_state + 1 : tck_cycle_count_ir_is_user_state;
always_ff @(posedge tck) tck_cycle_count_capture_dr_state <= (capture_dr) ? tck_cycle_count_capture_dr_state + 1 : tck_cycle_count_capture_dr_state;
always_ff @(posedge tck) tck_cycle_count_shift_dr_state <= (shift_dr) ? tck_cycle_count_shift_dr_state + 1 : tck_cycle_count_shift_dr_state;
always_ff @(posedge tck) tck_cycle_count_update_dr_state <= (update_dr) ? tck_cycle_count_update_dr_state + 1 : tck_cycle_count_update_dr_state;

localparam int COUNTERS = 8;
logic [$clog2(COUNTERS)-1:0] counter_sel;

localparam int CMD_WIDTH = 4;
typedef logic [CMD_WIDTH-1:0] cmd_t;
localparam cmd_t COUNTER_SEL_CMD = 4'b1001;

cmd_t cmd;
assign cmd = inbound_data[8-1:4]; // four MSB bits

always_ff @(posedge tck) begin: update_counter_sel
    if (inbound_valid && cmd == COUNTER_SEL_CMD) begin
        counter_sel <= inbound_data[3-1:0]; // three LSB bits
    end
end

localparam int OUTBAND_DATA_WIDTH = 3 + 1 + COUNTER_WIDTH;
logic [OUTBAND_DATA_WIDTH-1:0] outbound_data;

always_ff @(posedge tck) begin: counter_sel_mux
    unique case(counter_sel)
        0: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_any_state};
        1: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_test_logic_reset_state};
        2: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_run_test_idle_state};
        3: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_ir_is_user_state};
        4: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_capture_dr_state};
        5: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_shift_dr_state};
        6: outbound_data <= {counter_sel, 1'b0, tck_cycle_count_update_dr_state};
        7: outbound_data <= {counter_sel, 1'b0, STATIC_DATA};
    endcase
end

tap_encoder #(.DATA_WIDTH(OUTBAND_DATA_WIDTH)) tap_encoder_i (
    // TAP signals
        .tck(tck),
        .tdo(tdo),
        .test_logic_reset(test_logic_reset),
        .ir_is_user(ir_is_user),
        .capture_dr(capture_dr),
        .shift_dr(shift_dr),
    // Encoded signals
        .valid(1'b1),
        .data(outbound_data)
);

endmodule
`default_nettype wire
