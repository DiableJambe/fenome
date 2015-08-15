#include <iostream>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <fstream>
#include "fenome.hpp"
#include "error_correction.cpp"
#include "register_operations.cpp"

int main(int argc, char** argv) {

    std::string read_file = "./test_reads.txt";
    std::string kmer_file_name = "./test_kmers.txt";
    std::ifstream input_file(read_file.c_str());
    std::ifstream kmer_file(kmer_file_name.c_str());
    std::string read_string;
    std::string line_id;
    std::string line_misc;
    std::string quality_string("IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII00000000000000000000000000000000IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII");
    std::string kmer_string;
    int32_t read_length=112;
    int32_t kmer_length=30;
    int32_t threshold;
    uint8_t level0;
    uint8_t level1;
    uint8_t level2;
    uint8_t level3;
    int num_reads_processed = 0;
    int num_reads_per_iteration = 512;
    int num_kmers_per_iteration = 512 * 4;

    char* kmer_space;
    uint32_t** correction_space;
    char* candidate_space;
    char* read_space;
    int32_t* index_space;
    struct correction_item* correction_array;

    int32_t num_iterations = 4;
    std::string ddr_output_file_name = "./ddr3.hex";
    std::ofstream write_ddr(ddr_output_file_name.c_str());

    if (!write_ddr.is_open()) {
        std::cout << "Cannot open ./ddr3.hex" << std::endl;
        return -1;
    }

    uint32_t* ddr_space;
    if (posix_memalign((void**)&ddr_space, 128, 128 * 256) != 0) {
        std::cout << "ERROR!!!" << std::endl;
    }

    std::cout << "Assigned space for ddr space";
 
    open_device((uint64_t) 0)
    wait_for_idle(afu_h);
    clear_status(afu_h);

    std::cout << "Device has woken up" << std::endl;

    cxl_mmio_write64(afu_h,WRITE_BASE,(uint64_t)ddr_space);
    cxl_mmio_write32(afu_h,DDR3_BASE,0);
    cxl_mmio_write32(afu_h,CONTROL,SetControlRegister(DDR3_READ,0,0));
    cxl_mmio_write32(afu_h,START,0xdead);

    std::cout << "Completed initialization and triggered DDR reads ... Waiting ... " << std::endl;
   
    wait_for_idle(afu_h);
    
    //1. 

////First program solid k-mers into the bloom-filter
//    if (posix_memalign((void**)&kmer_space, 128, num_kmers_per_iteration * 64) != 0) {
//        std::cout << "ERROR!!!" << std::endl;
//    }
//
//    open_device((uint64_t) 0)
//    wait_for_idle(afu_h);
//    clear_status(afu_h);
//    if (!kmer_file.is_open()) {
//        std::cout << "Cannot open k-mer file!!!" << std::endl;
//        return -1;
//    }
//    int32_t num_kmers = 0;
//    while (std::getline(kmer_file, kmer_string)) {
//        memcpy(kmer_space + (num_kmers % num_kmers_per_iteration) * 64, kmer_string.c_str(), kmer_length);
//        num_kmers++;
//        if (num_kmers % num_kmers_per_iteration == 0) {
//            std::cout << "Completed collecting k-mers" << std::endl;
//            set_kmer_program_mode(afu_h, num_kmers_per_iteration, kmer_length, kmer_space);
//            Start;
//#ifdef DEBUG
//            FILE* debug = fopen("./debug", "w");
//            for (int x = 0; x < num_kmers_per_iteration; x++) {
//                char* kmerToPrint = kmer_space + x * 64;
//                for (int y = 63; y > 0; y--) {
//                    fprintf(debug,"%02x", kmerToPrint[y]);
//                }
//                fprintf(debug, "\n");
//            }
//#endif
//            //Wait for IDLE
//            bool success = wait_for_idle(afu_h);
//            if (!success) {
//                std::cout << "Cannot complete AFU transactions. Exiting!!!" << std::endl;
//                return -1;
//            }
//            clear_status(afu_h);
//            std::cout << "Completed iteration" << std::endl;
//        }
//    }
//
//    if (num_kmers % num_kmers_per_iteration != 0) {
//        std::cout << "The last set of k-mers going to be tested ... " << std::endl;
//        int32_t num_remaining = num_kmers % num_kmers_per_iteration;
//        set_kmer_program_mode(afu_h, num_remaining, kmer_length, kmer_space);
//        Start;
//        bool success = wait_for_idle(afu_h);
//        if (!success) {
//            std::cout << "Cannot complete AFU transactions. Exiting!!!" << std::endl;
//            return -1;
//        }
//        clear_status(afu_h);
//        std::cout << "Completed last iteration" << std::endl;
//    }
//
////First convert each read to a correction item
//    if (!(input_file.is_open())) {
//        std::cout << "Cannot open input file" << std::endl;
//        return 1;
//    }
//
//    //256 bytes per read = 2 cache lines = 2048 bits
//    if (posix_memalign((void**)&read_space, 128, num_reads_per_iteration * 256) != 0) {
//        std::cout << "ERROR!!! Cannot allocate aligned space for read_space" << std::endl;
//    }
//
//    //256 bytes per packed index space = 2 cache lines = 2048 bits = 32 * 2 * (32 indices)
//    if (posix_memalign((void**)&index_space, 128, num_reads_per_iteration * 256) != 0) {
//        std::cout << "ERROR!!! Cannot allocate aligned space for read_space" << std::endl;
//    }
//    
//    while (std::getline(input_file, read_string)) {
//        if (!std::getline(input_file, read_string)) {
//            std::cout << "Error in file format" << std::endl;
//            return 1;
//        }
//        if (!std::getline(input_file, quality_string)) {
//            std::cout << "Error in file format" << std::endl;
//            return 1;
//        }
//        if (!std::getline(input_file, quality_string)) {
//            std::cout << "Error in file format" << std::endl;
//            return 1;
//        }
//
//        char* read_item = read_space + 256 * (num_reads_processed % num_reads_per_iteration);
//        memcpy(read_space + 256 * (num_reads_processed % num_reads_per_iteration), read_string.c_str(), read_length);
//        read_item[255] = read_length;
//        num_reads_processed++;
//
//        //Flatten out stuff - in case it is all to go back to C
//        //correction_array[num_reads_processed].read_string    = (uint32_t*) read_space[num_reads_processed*2];
//        //correction_array[num_reads_processed].quality_string = (uint32_t*) read_space[num_reads_processed*2+1];
//        //correction_array[num_reads_processed].read_length    = read_string.length();
//        //correction_array[num_reads_processed].island_indices = (int32_t*) index_space[num_reads_processed];
//        if (num_reads_processed % num_reads_per_iteration == 0) {
//            int32_t num_corrections = 0;
//            uint64_t wed = 0;
//
//            std::cout << "Reads processed, proceeding to procure island information ... " << std::endl;
//           
//            //1. Profile the reads
//            set_read_profile_mode(afu_h, num_reads_per_iteration, kmer_length, index_space, read_space);
//            Start;
//
//            bool success = wait_for_idle(afu_h);
//            if (!success) {
//                std::cout << "ERROR! Read profile doesn't complete!!!" << std::endl;
//            }
//            clear_status(afu_h);
//
//            //Print the indices
//            for (int m = 0; m < num_reads_per_iteration; m++) { 
//                int32_t* index_base = index_space + 32 * 2 * m;
//                std::cout << "For " << m << "-th read" << std::endl;
//                for (int n = 0; n < 32; n++) {
//                    int position = index_base[2*n];
//                    int length = index_base[2*n+1];
//                    //if ((position != -1) && (length != -1)) {
//                        std::cout << "(" << position << "," << length << ")" << std::endl;
//                    //} else {
//                      //  break;
//                    //}
//                }
//            }
//            
//            ////2. Adjust solid islands
//            ////adjust_solid_islands(index_space,num_reads_per_iteration);
//
//            ////3. Set correction types for each read and collect reads to be corrected in a particular space
//            //num_corrections = set_correction_types(correction_array, num_reads_per_iteration, candidate_space, correction_space);
//
//            ////4. Correct errors
//            //set_read_correct_mode(afu_h, num_reads_per_iteration, threshold, kmer_length, level0, level1, level2, level3, candidate_space, correction_space);
//            //Start;
//
//            ////5. Post process each correction, and then combine
//            ////post_process_corrections(correction_array, num_reads_per_iteration);
//            //
//            ////TBD 9: Write out results
//
//            //for (int k = 0; k < num_corrections; k++) {
//            //    delete[] correction_space[k];
//            //    for (int m = 0; m < 32; m++) {
//            //        delete[] candidate_space[32*k+m];
//            //    }
//            //}
//
//            //for (int k = 0; k < num_reads_per_iteration; k++) {
//            //    delete[] correction_array[k].candidates;
//            //    delete[] correction_array[k].start_position;
//            //    delete[] correction_array[k].end_position;
//            //}
//        }
//    }
//
//    if (num_reads_processed % num_reads_per_iteration != 0) {
//        int32_t num_corrections = 0;
//        uint64_t wed = 0;
//
//        std::cout << "Processing last read batch for island information ... " << std::endl;
//       
//        //1. Profile the reads
//        set_read_profile_mode(afu_h, num_reads_processed % num_reads_per_iteration, kmer_length, index_space, read_space);
//        Start;
//
//        bool success = wait_for_idle(afu_h);
//        if (!success) {
//            std::cout << "ERROR! Read profile doesn't complete!!!" << std::endl;
//        }
//        clear_status(afu_h);
//
//        for (int m = 0; m < num_reads_processed % num_reads_per_iteration; m++) { 
//            int32_t* index_base = index_space + 32 * 2 * m;
//            std::cout << "For " << m << "-th read" << std::endl;
//            for (int n = 0; n < 32; n++) {
//                int position = index_base[2*n];
//                int length = index_base[2*n+1];
//                //if ((position != -1) && (length != -1)) {
//                    std::cout << "(" << position << "," << length << ")" << std::endl;
//                //} else {
//                 //   break;
//                //}
//            }
//        }
//    }

    
//    open_device((uint64_t) 0)
//    clear_status(afu_h);
// 
//    std::ifstream test_file("/home/aramach/Downloads/app/stimulus.txt");
//    if (!test_file.is_open()) {
//        std::cout << "ERROR!! Cannot open stimulus file" << std::endl;
//    }
//
//    if (posix_memalign((void**)&read_space, 128, num_reads_per_iteration * 256 *2) != 0) {
//        std::cout << "ERROR!!!" << std::endl;
//    }
//
//    if (posix_memalign((void**)&candidate_space, 128, num_reads_per_iteration * 256 * 32) != 0) {
//        std::cout << "ERROR!!!" << std::endl;
//    }
//
//    num_reads_processed = 0;
//    char quality_string_c[113]; //= quality_string.c_str();
//    memcpy(quality_string_c, quality_string.c_str(), read_length);
//    for (int p = 40; p < 70; p++) {
//        quality_string_c[p] = 0;
//    }
//    while (std::getline(test_file, read_string)) {
//        uint32_t start_position, end_position;
//        char read_string_c[113];
//        sscanf(read_string.c_str(), "%s %d %d", read_string_c, &start_position, &end_position); read_string_c[read_length] = '\0';
//        std::cout << "Read : " << read_string_c << " start: " << (char) start_position << " end: " << (char) end_position << std::endl;
//
//        memcpy(read_space + 512 * (num_reads_processed % num_reads_per_iteration), read_string_c, read_length);
//        memcpy(read_space + 512 * (num_reads_processed % num_reads_per_iteration) + 256, quality_string_c, read_length);
//
//        char* read_item = read_space + 512 * (num_reads_processed % num_reads_per_iteration);
// 
//        read_item[255] = read_length;
//        read_item[254] = start_position;
//        read_item[253] = end_position;
//       
//        num_reads_processed++;
//
//        if (num_reads_processed % num_reads_per_iteration == 0) {
//            set_read_correct_mode(afu_h, num_reads_per_iteration, 1, kmer_length, 0, 20, 60, 80, candidate_space, read_space);
//            Start;
//            bool success = wait_for_idle(afu_h);
//            if (!success) {
//                std::cout << "ERROR! Read profile doesn't complete!!!" << std::endl;
//                return -1;
//            }
//            clear_status(afu_h);
//
//            for (int m = 0; m < num_reads_per_iteration; m++) {
//                char* candidate_local_space = candidate_space + m * 256 * 32;
//                char* read = read_space + m * 512; read[read_length] = '\0';
//                int32_t num_candidates = (int32_t) candidate_local_space[255]; //The last byte of every read provides us with the number of candidates
//                //std::cout << "Read " << read << " has " << num_candidates << " candidates" << std::endl;
//                printf("Candidate for %s is at %lu\n", read, (uint64_t) candidate_local_space);
//                printf("Read %s has %d candidates\n", read, num_candidates);
//                for (int n = 0; n < num_candidates; n++) {
//                    char* candidate = candidate_local_space + n * 256;
//                    int32_t num_candidates_to_print = (int32_t) candidate[255];
//                    candidate[read_length] = '\0';
//                    //candidate[read_length] = '\0';
//                    printf("Read:%s:%s:%d\n", read,candidate,num_candidates_to_print);
//                }
//                std::cout << "Completed printing candidates ... " << std::endl;
//            }
//        }
//    }
//
//    if (num_reads_processed % num_reads_per_iteration != 0) {
//        std::cout << "Entering the final iteration" << std::endl;
//        set_read_correct_mode(afu_h, num_reads_processed % num_reads_per_iteration, 1, kmer_length, 0, 20, 60, 80, candidate_space, read_space);
//        Start;
//        bool success = wait_for_idle(afu_h);
//        if (!success) {
//            std::cout << "ERROR! Read profile doesn't complete!!!" << std::endl;
//            return -1;
//        }
//        clear_status(afu_h);
//
//        for (int m = 0; m < num_reads_processed % num_reads_per_iteration; m++) {
//            char* candidate_local_space = candidate_space + m * 256 * 32;
//            char* read = read_space + m * 512; read[read_length] = '\0';
//            int32_t num_candidates = (int32_t) candidate_local_space[255]; //The last byte of every read provides us with the number of candidates
//            printf("Candidate for %s is at %lu\n", read, (uint64_t) candidate_local_space);
//            printf("Read %s has %d candidates\n", read, num_candidates);
//            for (int n = 0; n < num_candidates; n++) {
//                char* candidate = candidate_local_space + n * 256; 
//                int32_t num_candidates_to_print = (int32_t) candidate[255];
//                candidate[read_length] = '\0';
//                //std::cout << "Read " << read << ":" << candidate << ":" << num_candidates << std::endl;
//                printf("Read:%s:%s:%d\n",read,candidate,num_candidates_to_print);
//            }
//            std::cout << "Completed printing candidates ... " << std::endl;
//        }
//    }
//
    close_device

    std::cout << "Closing program ... " << std::endl;
    return 0;
}

//Test PSL - strategy 1
//1. MMIO writes ...
//2. Solid islands checking
//3. Read Error correction
