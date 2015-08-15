void inline set_kmer_program_mode(struct cxl_afu_h* afu_h, uint32_t num_kmers_per_payload, int32_t kmer_length, char* kmer_space) {
    uint32_t control   = SetControlRegister(PROGRAM,0,kmer_length);
    uint64_t read_base = (uint64_t) kmer_space;
//Note : A single "item" in the AFU is two cache lines for the PROGRAM and SOLID_ISLANDS modes. This is 256 bytes = 4 k-mers.
//However, the AFU *REQUIRES* the number of items to process to be even in these two modes. Thus, we need the number of k-mers required to be a multiple of 8.
//Duplicate k-mers from the previous iteration as required (this will automatically happen).
//The number of items is number of k-mers / 4.
    if (num_kmers_per_payload % 8 != 0) {
        num_kmers_per_payload = num_kmers_per_payload + (8 - (num_kmers_per_payload % 8));
    }
    cxl_mmio_write32(afu_h,NUM_ITEMS,num_kmers_per_payload/4);
    cxl_mmio_write32(afu_h,CONTROL,control);
    cxl_mmio_write64(afu_h,READ_BASE,read_base);
}

void inline set_read_profile_mode(struct cxl_afu_h* afu_h, uint32_t num_reads_per_payload, int32_t kmer_length, int32_t* index_space, char* read_space) {
    uint32_t control    = SetControlRegister(SOLID_ISLANDS,0,kmer_length);
    uint64_t write_base = (uint64_t) index_space;
    uint64_t read_base  = (uint64_t) read_space;
//NOTE: The read-lane in the AFU corresponds to 4096 bits or 512 bytes. This is equivalent to two reads. A single item is one read.
//Hence we should program an even number of reads
    cxl_mmio_write32(afu_h,CONTROL,control);
    cxl_mmio_write32(afu_h,NUM_ITEMS,(num_reads_per_payload%2 == 0)? num_reads_per_payload : num_reads_per_payload+1);
    cxl_mmio_write64(afu_h,WRITE_BASE,write_base);
    cxl_mmio_write64(afu_h,READ_BASE,read_base);
}

void inline set_read_correct_mode(struct cxl_afu_h* afu_h, uint32_t num_reads_per_payload, uint8_t threshold, int32_t kmer_length, uint8_t level0, uint8_t level1, uint8_t level2, uint8_t level3, char* candidate_space, char* read_space) {
    uint32_t control    = SetControlRegister(CORRECTION,threshold,kmer_length);
    uint32_t qthreshold = SetThresholdsLevels(level0,level1,level2,level3);
    uint64_t write_base = (uint64_t) candidate_space;
    uint64_t read_base  = (uint64_t) read_space;
//Note: The read lane is 8 * 512 bits wide (equivalently). This is equal to one read and one quality score component. This is hence, a single item.
    cxl_mmio_write32(afu_h,CONTROL,control);
    cxl_mmio_write32(afu_h,NUM_ITEMS,num_reads_per_payload);
    cxl_mmio_write32(afu_h,THRESHOLD,qthreshold);
    cxl_mmio_write64(afu_h,READ_BASE,read_base);
    cxl_mmio_write64(afu_h,WRITE_BASE,write_base);
}

bool inline wait_for_idle(struct cxl_afu_h* afu_h) {
    int32_t total_wait_cycles = (2 << 25);
    int32_t num_wait_cycles = 0;
    bool success = false;
    uint32_t val[1];
    while (num_wait_cycles < total_wait_cycles) {
        cxl_mmio_read32(afu_h, STATUS, val);
        if ((*val & 0x43) == 0x43) {      //PLL LOCK, local_init_done, status = 1
            success = true;
            break;
        }
        num_wait_cycles++;
    }
    return success;
}

bool inline wait_for_ddr3_init(struct cxl_afu_h* afu_h) {
    int32_t control = SetControlRegister(DDR3_INIT,0,0);
    bool success = false;
    uint32_t val;
    int32_t num_wait_cycles = 0;
    while(num_wait_cycles < (2 << 26)) {
        cxl_mmio_read32(afu_h, STATUS, &val);
        if (val & DDR3_INIT_DONE) {
            success = true;
            break;
        }
        num_wait_cycles++;
    }
    return success;
}

void inline clear_status(struct cxl_afu_h* afu_h) {
    cxl_mmio_write32(afu_h,STATUS,0x0);
}
