package require Vivado

namespace eval counter_enum {
    # Define a variable holding a flat list of key-value pairs
    variable tck_cycles_enum_list {
        TCK_CYCLE_COUNT_ANY_STATE 0
        TCK_CYCLE_COUNT_TEST_LOGIC_RESET_STATE 1
        TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE 2
        TCK_CYCLE_COUNT_IR_IS_USER_STATE 3
        TCK_CYCLE_COUNT_CAPTURE_DR_STATE 4
        TCK_CYCLE_COUNT_SHIFT_DR_STATE 5
        TCK_CYCLE_COUNT_UPDATE_DR_STATE 6
        STATIC_DATA 7
    }
    array set tck_cycles_enum_map $tck_cycles_enum_list
}

proc ::parse_named_arguments {arg_list} {
    set arg_dict {}
    foreach arg_pair $arg_list {
        if {[regexp {([^=]+)=(.+)} $arg_pair -> key value]} {
            dict set arg_dict $key $value
        }
    }
    return $arg_dict
}

proc ::build {arg_dict} {
    create_project -part [dict get $arg_dict PART] -in_memory
    read_verilog -sv [glob ../*.sv]
    read_xdc [glob ../*.xdc]

    set directive RuntimeOptimized; # speed-run the build process
    synth_design -top shell \
        -verilog_define USER_LOGIC_DEF=user_logic \
        -directive $directive \
        -flatten_hierarchy none \
        -debug_log -verbose
    opt_design \
        -directive $directive \
        -debug_log -verbose
    place_design \
        -directive $directive \
        -timing_summary \
        -debug_log -verbose
    route_design \
        -directive $directive \
        -tns_cleanup \
        -debug_log -verbose
    write_checkpoint -force project.dcp

    # least crowded firmware
    report_clock_networks -endpoints_only -file clock_networks.txt
    report_clock_utilization -file clock_utilization.txt
    report_control_sets -hierarchical -file control_sets.txt
    report_datasheet -show_all_corners -file datasheet.txt
    report_design_analysis -file design_analysis.txt -quiet
    report_disable_timing -user_disabled -file disable_timing.txt
    report_drc -no_waivers -file drc.txt
    report_exceptions -file exceptions.txt
    report_high_fanout_nets -timing -load_types -max_nets 99 -file high_fanout_nets.txt
    report_methodology -no_waivers -file methodology.txt
    report_power -file power.txt
    report_qor_assessment -file qor_assessment.txt -full_assessment_details -quiet
    report_qor_suggestions -file qor_suggestions.txt -report_all_suggestions -quiet
    report_timing_summary -slack_lesser_than 20 -max_paths 1 -file timing_summary.txt; # lol
    report_utilization -file utilization.txt
    catch {report_utilization -hierarchical -hierarchical_min_primitive_count 0 -file hierarchical_utilization.txt}

    set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
    set_property BITSTREAM.CONFIG.USR_ACCESS TIMESTAMP [current_design]
    set_property BITSTREAM.CONFIG.USERID [dict get $arg_dict GIT_COMMIT] [current_design]
    write_bitstream -force -logic_location_file -file fpga.bit
}

proc ::lint {arg_dict} {
    create_project -part [dict get $arg_dict PART] -in_memory
    read_verilog -sv [glob ../*.sv]
    synth_design -top [lindex [find_top] 0] \
        -lint -file lint.txt -debug_log -verbose
}

proc ::program {} {
    open_hw_manager -quiet
    connect_hw_server -quiet
    open_hw_target -quiet
    set_property PROGRAM.FILE [glob *.bit] [current_hw_device]
    program_hw_devices [current_hw_device]
    refresh_hw_device -quiet
}

proc ::run_jtag_tap {} {
    # cycle target connection
    open_hw_manager -quiet
    connect_hw_server -quiet
    open_hw_target -quiet
    close_hw_target -quiet
    open_hw_target -jtag_mode on -quiet

    # set FPGA PL TAP IR to USER4
    run_state_hw_jtag RESET; # this clears instruction register
    run_state_hw_jtag IDLE
    set zynq7_ir_length 10; # must match FPGA device family / SLR count
    set zynq7_ir_user4 0x3e3; # idem
    scan_ir_hw_jtag $zynq7_ir_length -tdi $zynq7_ir_user4

    set counter_sel_cmd 0x9
    foreach {counter_name counter_sel} $::counter_enum::tck_cycles_enum_list {
        set hex_cmd 0x[format %03x [expr ($counter_sel_cmd << 4) + $counter_sel]]
        #puts "Name: $counter_name, hex_cmd: $hex_cmd"
        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "Readback $counter_name: [format %d [expr ($readback_data & 0x0fffffff)]] (0x[format %08x $readback_data])"
    }

    # Consecutive reads of idle counter value

        set counter_sel $::counter_enum::tck_cycles_enum_map(TCK_CYCLE_COUNT_RUN_TEST_IDLE_STATE)
        set hex_cmd 0x[format %03x [expr ($counter_sel_cmd << 4) + $counter_sel]]

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data & 0x0fffffff)]] ($readback_data)"

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data_next 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data_next & 0x0fffffff)]] ($readback_data)"
        puts "Difference: [format %d [expr ($readback_data_next - $readback_data)]]"

    # Consecutive reads of idle counter value with 100x `run_state_hw_jtag -state IDLE IDLE` between

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data & 0x0fffffff)]] ($readback_data)"

        # cycle tck for purging data stuck between register stages
        for {set i 0} {$i<100} {incr i} {
            run_state_hw_jtag -state IDLE IDLE;
        }

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data_next 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data_next & 0x0fffffff)]] ($readback_data)"
        puts "Difference after 100x `run_state_hw_jtag -state IDLE IDLE`: [format %d [expr ($readback_data_next - $readback_data)]]"

    # Consecutive reads of idle counter value with 100x `run_state_hw_jtag -state IDLE IDLE` between

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data & 0x0fffffff)]] ($readback_data)"

        # cycle tck for purging data stuck between register stages
        for {set i 0} {$i<100} {incr i} {
            run_state_hw_jtag IDLE;
        }

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data_next 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data_next & 0x0fffffff)]] ($readback_data)"
        puts "Difference after 100x `run_state_hw_jtag IDLE`: [format %d [expr ($readback_data_next - $readback_data)]]"

    # Consecutive reads of idle counter value with 100x `run_state_hw_jtag DRPAUSE` + `run_state_hw_jtag IDLE` between

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data & 0x0fffffff)]] ($readback_data)"

        # cycle tck for purging data stuck between register stages
        for {set i 0} {$i<100} {incr i} {
            run_state_hw_jtag DRPAUSE
            run_state_hw_jtag IDLE
        }

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data_next 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP run-test-idle tck count: [format %d [expr ($readback_data_next & 0x0fffffff)]] ($readback_data)"
        puts "Difference after 100x `run_state_hw_jtag DRPAUSE` + `run_state_hw_jtag IDLE`: [format %d [expr ($readback_data_next - $readback_data)]]"

    # Report value for IR

        set counter_sel $::counter_enum::tck_cycles_enum_map(TCK_CYCLE_COUNT_IR_IS_USER_STATE)
        set hex_cmd 0x[format %03x [expr ($counter_sel_cmd << 4) + $counter_sel]]

        scan_dr_hw_jtag 9 -tdi ${hex_cmd}; # extra bit for ARM DAP bypass
        run_state_hw_jtag IDLE; # run TAP through `UPDATE-DR` state
        set readback_data 0x[scan_dr_hw_jtag 32 -tdi 0]
        puts "TAP IR USER4 counter: [format %d [expr ($readback_data & 0x0fffffff)]]"
}

proc run {argv} {
    set arg_dict [::parse_named_arguments $argv]
    switch [dict get $arg_dict TASK] {
        "all" {
            ::build $arg_dict
            ::program
            ::run_jtag_tap
        }
        "build" {
            ::build $arg_dict
        }
        "program" {
            ::program
        }
        "run" {
            ::program
            ::run_jtag_tap
        }
        "lint" {
            ::lint
        }
        default {
            ::build $arg_dict
        }
    }
}

if {[catch {::run $argv}]} {
    # Fix long Vivado exit delay by manually closing the project prior to quitting
    puts "### Exception in [file normalize [info script]] ###"
    puts $::errorInfo
    close_project -quiet
}
