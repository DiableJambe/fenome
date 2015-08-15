#Untoward clock domain crossings
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|mode*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|threshold*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|kmerLength*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|last_workload*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold0*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold1*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold2*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold3*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|read_base_addr*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|write_base_addr*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_reads_read*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_reads_written*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_items_to_process*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|status*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|ddr3_base_address*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|mode*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|threshold*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|kmerLength*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|last_workload*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold0*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold1*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold2*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|qThreshold3*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|read_base_addr*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|write_base_addr*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_reads_read*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_reads_written*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|num_items_to_process*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|status*
set_multicycle_path -hold 1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslMMIO:mmio|ddr3_base_address*

#write-buffer address field - write_buffer_wptr
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr*
set_multicycle_path -hold  1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied*
set_multicycle_path -hold  1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer*
set_multicycle_path -hold  1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied*
set_multicycle_path -hold  1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied*
set_multicycle_path -setup 2 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr*
set_multicycle_path -hold  1 -from psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_location_occupied* -to psl_accel:a0|afu:afu0|pslInterface:psl|pslBuffer:buffer|write_buffer_wptr*
