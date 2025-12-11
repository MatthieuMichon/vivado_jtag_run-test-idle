`timescale 1ps/1ps
`default_nettype none

module user_logic_tb;

logic tck, tdi, tdo;
logic test_logic_reset, run_test_idle, ir_is_user, capture_dr, shift_dr, update_dr;

initial begin
    tck = 0;
    forever #1 tck = ~tck;
end

localparam int IR_LENGTH = 6;

typedef enum {
    TEST_LOGIC_RESET,
    RUN_TEST_IDLE,
    SELECT_DR_SCAN,
    CAPTURE_DR,
    SHIFT_DR,
    EXIT1_DR,
    PAUSE_DR,
    EXIT2_DR,
    UPDATE_DR,
    IR
} state_t;

localparam int COUNTER_WIDTH = 28;
typedef logic [COUNTER_WIDTH-1:0] count_t;

localparam int CMD_WIDTH = 4;
typedef logic [CMD_WIDTH-1:0] cmd_t;
localparam cmd_t COUNTER_SEL_CMD = 4'b1001;

localparam int COUNTERS = 8;

typedef enum logic [$clog2(COUNTERS)-1:0] {
    TCK_CYCLE_COUNT_ANY_STATE = 0,
    TCK_CYCLE_COUNT_TEST_LOGIC_RESET_STATE,
    TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE,
    TCK_CYCLE_COUNT_IR_IS_USER_STATE,
    TCK_CYCLE_COUNT_CAPTURE_DR_STATE,
    TCK_CYCLE_COUNT_SHIFT_DR_STATE,
    TCK_CYCLE_COUNT_UPDATE_DR_STATE,
    STATIC_DATA
} counter_t;

localparam int READBACK_DATA_WIDTH = 3 + 1 + COUNTER_WIDTH;
typedef logic [READBACK_DATA_WIDTH-1:0] readback_data_t;


task automatic run_state_hw_jtag(state_t tap_state);
    unique case (tap_state)
        TEST_LOGIC_RESET: begin
            test_logic_reset = 1'b1;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        RUN_TEST_IDLE: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b1;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        SELECT_DR_SCAN: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        CAPTURE_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b1;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        SHIFT_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b1;
            update_dr = 1'b0;
        end
        EXIT1_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        PAUSE_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        EXIT2_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
        UPDATE_DR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b1;
        end
        IR: begin
            test_logic_reset = 1'b0;
            run_test_idle = 1'b0;
            capture_dr = 1'b0;
            shift_dr = 1'b0;
            update_dr = 1'b0;
        end
    endcase
endtask

task automatic readback_counter(
    input counter_t selected_counter,
    output readback_data_t readback_data
);
    byte cmd = {COUNTER_SEL_CMD, 1'b0, selected_counter};

    // Send command

        run_state_hw_jtag(SELECT_DR_SCAN);
        @(posedge tck);
        run_state_hw_jtag(CAPTURE_DR);
        @(posedge tck);
        run_state_hw_jtag(SHIFT_DR);
        for (int j=0; j<8; j++) begin
            tdi = cmd[j];
            @(posedge tck); // commit bit shift
        end
        run_state_hw_jtag(EXIT1_DR);
        @(posedge tck);
        run_state_hw_jtag(UPDATE_DR);
        @(posedge tck);
        run_state_hw_jtag(RUN_TEST_IDLE);
        @(posedge tck);

    // Readback value

        run_state_hw_jtag(RUN_TEST_IDLE);
        @(posedge tck);
        run_state_hw_jtag(SELECT_DR_SCAN);
        @(posedge tck);
        run_state_hw_jtag(CAPTURE_DR);
        @(posedge tck);
        run_state_hw_jtag(SHIFT_DR);
        tdi = 1'b0; // replicate TCL script behavior
        for (int j=0; j<$bits(readback_data); j++) begin
            readback_data[j]= tdo;
            @(posedge tck); // commit bit shift
        end
        run_state_hw_jtag(EXIT1_DR);
        @(posedge tck);
        run_state_hw_jtag(UPDATE_DR);
        @(posedge tck);
        run_state_hw_jtag(RUN_TEST_IDLE);
        @(posedge tck);
endtask

initial begin
    readback_data_t fpga_counter_val, fpga_counter_val_next;
    counter_t counter_iterator;

    // set initial values

        ir_is_user = 1'b0;
        run_state_hw_jtag(TEST_LOGIC_RESET);
        @(posedge tck);
        tdi = 1'b0; // whatever value
        run_state_hw_jtag(RUN_TEST_IDLE);
        @(posedge tck);

    // set instruction register to `USER4`

        run_state_hw_jtag(SELECT_DR_SCAN);
        @(posedge tck);
        run_state_hw_jtag(IR); // SELECT_IR_SCAN
        @(posedge tck);
        run_state_hw_jtag(IR); // CAPTURE_IR
        @(posedge tck);
        for (int j=0; j<IR_LENGTH; j++) begin
            run_state_hw_jtag(IR); // SHIFT_IR
            @(posedge tck);
        end
        run_state_hw_jtag(IR); // EXIT1_IR
        @(posedge tck);
        run_state_hw_jtag(IR); // UPDATE_IR
        @(posedge tck);
        ir_is_user = 1'b1;
        run_state_hw_jtag(RUN_TEST_IDLE);
        @(posedge tck);

    // Read from all counters

        counter_iterator = counter_iterator.first();
        do begin: iterate_over_all_counters
            readback_counter(counter_iterator, fpga_counter_val);
            $display("Readback %s: %d (0x%h)", counter_iterator.name(), fpga_counter_val[28-1:0], fpga_counter_val);
            counter_iterator = counter_iterator.next();
        end while (counter_iterator != counter_iterator.first());

    // Consecutive reads of idle counter value

        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val[28-1:0], fpga_counter_val);
        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val_next);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val_next[28-1:0], fpga_counter_val_next);
        $display("Difference: %d", fpga_counter_val_next[28-1:0] - fpga_counter_val[28-1:0]);

    // Consecutive reads of idle counter value with 100x `run_state_hw_jtag(RUN_TEST_IDLE)` between

        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val[28-1:0], fpga_counter_val);
        for (int j=0; j<100; j++) begin
            run_state_hw_jtag(RUN_TEST_IDLE);
            @(posedge tck);
        end
        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val_next);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val_next[28-1:0], fpga_counter_val_next);
        $display("Difference after 100x `run_state_hw_jtag(RUN_TEST_IDLE)`: %d", fpga_counter_val_next[28-1:0] - fpga_counter_val[28-1:0]);

    // Consecutive reads of idle counter value with 100x `run_state_hw_jtag(RUN_TEST_IDLE)` between

        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val[28-1:0], fpga_counter_val);
        for (int j=0; j<100; j++) begin
            // leaving RUN_TEST_IDLE state
            run_state_hw_jtag(SELECT_DR_SCAN);
            @(posedge tck);
            run_state_hw_jtag(CAPTURE_DR);
            @(posedge tck);
            run_state_hw_jtag(EXIT1_DR);
            @(posedge tck);
            run_state_hw_jtag(PAUSE_DR);
            @(posedge tck);
            run_state_hw_jtag(EXIT2_DR);
            @(posedge tck);
            run_state_hw_jtag(UPDATE_DR);
            @(posedge tck);
            run_state_hw_jtag(RUN_TEST_IDLE);
            @(posedge tck);
        end
        readback_counter(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE, fpga_counter_val_next);
        $display("TAP run-test-idle tck count: %d (0x%h)", fpga_counter_val_next[28-1:0], fpga_counter_val_next);
        $display("Difference after 100x `run_state_hw_jtag(PAUSE_DR -> RUN_TEST_IDLE)`: %d", fpga_counter_val_next[28-1:0] - fpga_counter_val[28-1:0]);

    $finish;
end

user_logic user_logic_i (
    // BSCAN signals
        .tck(tck),
        .tdi(tdi),
        .tdo(tdo),
        .test_logic_reset(test_logic_reset),
        .run_test_idle(run_test_idle),
        .ir_is_user(ir_is_user),
        .capture_dr(capture_dr),
        .shift_dr(shift_dr),
        .update_dr(update_dr));

endmodule
`default_nettype wire
