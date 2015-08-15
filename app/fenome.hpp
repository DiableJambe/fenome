//#define DEBUG

extern "C" {
    #include <stdint.h>
    #include "libcxl.h"
}

//A candidate correction - contains a string representing the correction, a map of the correction, and meta-data regarding it
struct island_corrections {
    char* read_string;                                //Each candidate 
    uint32_t* candidate_map;
    int32_t read_length, start_position, end_position;
};

//An array of candidates for different types of corrections of a given read
struct correction_item {
    char* read_string;
    char* quality_string;
    int32_t* island_indices;
    int32_t read_length;
    int32_t num_islands;
    int32_t trim_3_prime;
    int32_t trim_5_prime;
    uint64_t read_id;

    struct candidate* candidates;
    int32_t* start_position;
    int32_t* end_position;
};

//Shortcut to initialie 2D arrays
#define allocate(TYPE,var,X,Y) \
    { \
        char* space; \
        var = (TYPE**) malloc(sizeof(TYPE*) * X); \
        posix_memalign(&space,128,sizeof(TYPE)*X*Y); \
        for (int i = 0; i < X; i++) { \
            var[i] = (TYPE*) (space + X * sizeof(TYPE)); \
        } \
    }

#define open_device(wed) \
    struct cxl_afu_h* afu_h; \
    afu_h = cxl_afu_next(NULL); \
    if (!afu_h) { \
        std::cout << "No AFU found!!!" << std::endl; \
        return -1; \
    } \
    afu_h = cxl_afu_open_h(afu_h, CXL_VIEW_DEDICATED); \
    if (!afu_h) { \
        std::cout << "Cannot open AFU!!!" << std::endl; \
        return -1; \
    } \
    cxl_afu_attach(afu_h, (uint64_t)wed); \
    if (cxl_mmio_map(afu_h, CXL_MMIO_LITTLE_ENDIAN) < 0) { \
        std::cout << "Cannot map MMIO!!!" << std::endl; \
        return -1; \
    }

#define close_device \
    cxl_mmio_unmap(afu_h); \
    cxl_afu_free(afu_h);

#define FIVE_PRIME 0
#define BETWEEN 1
#define THREE_PRIME 2
#define NO_SOLID 3

//Register addresses
#define CONTROL        (0x2 << 2)
#define THRESHOLD      (0x3 << 2)
#define READ_BASE      (0x4 << 2)
#define WRITE_BASE     (0x6 << 2)
#define READS_RECEIVED (0x8 << 2)
#define READS_WRITTEN  (0x9 << 2)
#define NUM_ITEMS      (0xa << 2)
#define START          (0x10 << 2)
#define RESET          (0x20 << 2)
#define STATUS         (0x30 << 2)
#define DDR3_BASE      (0x40 << 2)

//AFU mode 
#define CORRECTION     2 
#define SOLID_ISLANDS  1
#define PROGRAM        0
#define DDR3_INIT      4
#define DDR3_READ      5
#define DDR3_WRITE     6

//status register
#define DDR3_INIT_DONE (1 << 5)

//Register fields
#define SetControlRegister(mode,threshold,kmerlength) ((mode & 7) | ((threshold & 3) << 3) | ((kmerlength & 0xff) << 8))
#define SetThresholdsLevels(level0,level1,level2,level3) (((level3 & 0xff) << 24) | ((level2 & 0xff) << 16) | ((level1 & 0xff) << 8) | (level0 & 0xff))
#define Start cxl_mmio_write32(afu_h,START,0xdead)
#define Reset cxl_mmio_write32(afu_h,RESET,0xdead)

//Function prototypes
void inline set_kmer_program_mode(struct cxl_afu_h* afu_h ,uint32_t num_kmers_per_payload, int32_t kmer_length, char* kmer_space);
                                                     //Set AFU to do solid k-mer programming
void inline set_read_profile_mode(struct cxl_afu_h* afu_h, uint32_t num_reads_per_payload, int32_t kmer_length, int32_t* index_space, char* read_space);
                                                     //Set AFU to do profiling of the reads and return the maps
void inline set_read_correct_mode(struct cxl_afu_h* afu_h, uint32_t num_reads_per_payload, uint8_t threshold, int32_t kmer_length, uint8_t level0, uint8_t level1, uint8_t level2, uint8_t level3, char* candidate_space, char* read_space);
                                                     //Set AFU to do error correction of reads and return candidates
bool inline wait_for_idle(struct cxl_afu_h* afu_h, int32_t total_wait_cycles);
                                                     //Wait for AFU operations to complete
bool inline wait_for_ddr3_init(struct cxl_afu_h*);
                                                     //Put DDR3 in init mode and poll to see whether init is done
void inline clear_status(struct cxl_afu_h* afu_h);
                                                     //Clear the status register
void adjust_solid_islands(int32_t** index_space, uint32_t num_items);
                                                     //Code to adjust solid island space - reused from GENE
int set_correction_types(struct correction_item* correction_array, uint32_t num_items, uint32_t** candidate_space, uint32_t** correction_space);
                                                     //Set the required types of corrections and allocate space in the common candidate space
void set_correction_map(struct correction_item* correction_array, uint32_t num_items);
                                                     //Function runs through each item and fixes the candidate map for each candidate
void post_process_corrections(struct correction_item* correction_array, uint32_t num_items);
                                                     //Do post processing on candidates - reused from GENE
