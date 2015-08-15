void adjust_solid_islands(int32_t** index_space, uint32_t num_items);
                                                                          //TBD: Adapt from GENE code

///Each read is primed for correction
//int set_correction_types(struct correction_item* correction_array, uint32_t num_items, uint32_t** candidate_space, uint32_t** correction_space) {

//    int32_t num_islands_total = 0;
//
//    for (int i = 0; i < num_items; i++) {
//        struct correction_item read_obj = correction_array[i];
//
//        int32_t* index_space = read_obj.island_indices;
//        int32_t read_length  = read_obj.read_length;
//        int32_t num_islands  = 0;
//
//        //Count the number of non-solid islands within the read
//        for (int j = 0; j < 31; j++) {
//            int32_t this_start_position = index_space[2*j];
//            int32_t this_length         = index_space[2*j+1];
//
//            int32_t prev_start_position = index_space[2*(j-1)];
//            int32_t prev_length         = index_space[2*(j-1)+1];
//            
//            //Case 1: There is no solid island in the read
//            if ((j == 0) && (this_start_position == -1)) {
//                num_islands++;
//                break;
//            }
//
//            //Case 2: The first island is not at the beginning of the read
//            if ((j == 0) && (this_start_position > 0)) {
//                num_islands++;
//                continue;
//            }
//
//            //Case 3: The current island is a dud. Check whether the previous island extended till the end of the read
//            if (this_start_position == -1) {
//                if (prev_start_position + prev_length < read_length) {
//                    num_islands++;
//                }
//                break;
//            }
//          
//            //Case 4: The previous island didn't extend up to this one - there is a non-solid island in between
//            if (prev_start_position + prev_length - 1 < this_start_position) {
//                num_islands++;
//            }
//        }
//
//        read_obj.start_position = new int[num_islands];
//        read_obj.end_position   = new int[num_islands];
//        read_obj.candidates     = new struct candidate[num_islands];
//        read_obj.num_islands    = num_islands;
//
//        num_islands_total += num_islands;
//
//        int32_t index_counter = 0;
//
//        //Redo the loop to get the numbers in this time
//        for (int j = 0; j < 31; j++) {
//            int32_t this_start_position = index_space[2*j];
//            int32_t this_length         = index_space[2*j+1];
//            int32_t prev_start_position = j > 0 ? index_space[2*(j-1)] : -1;
//            int32_t prev_length         = j > 0 ? index_space[2*(j-1)+1] : -1;
//
//            if ((j == 0) && (this_start_position == -1)) {
//                read_obj.start_position[index_counter++] = 0;
//                read_obj.end_position[index_counter++] = read_obj.read_length-1;
//                break;
//            }
//
//            if ((j == 0) && (this_start_position > 0)) {
//                read_obj.start_position[index_counter++] = this_start_position - 1;
//                read_obj.end_position[index_counter++]   = 0;
//                continue;
//            }
//
//            if (this_start_position == -1) {
//                if (prev_start_position + prev_length < read_length) {
//                    read_obj.start_position[index_counter++] = prev_start_position + prev_length;
//                    read_obj.end_position[index_counter++]   = read_obj.read_length-1;
//                    break;
//                }
//            }
//
//            if (prev_start_position + prev_length - 1 < this_start_position) {
//                read_obj.start_position[index_counter++] = prev_start_position + prev_length;
//                read_obj.end_position[index_counter++]   = this_start_position - 1;
//            }
//        }
//    }
//
//    //This is the total number of islands, so we need 32 * num_islands_total candidates
//    //allocate(uint32_t, candidate_space, num_islands_total * 32 , 64)
//    //allocate(uint32_t, correction_space, num_islands_total, 64)
//
//    int32_t island_traverser = 0;
//    
//    //Create correction-space and allocate candidate space
//    for (int i = 0; i < num_items; i = i + 1) {
//        struct correction_item read_obj = correction_array[i];
//        int32_t num_islands = read_obj.num_islands;
//
//        for (int j = 0; j < num_islands; j++, island_traverser++) {
//            read_obj.candidates[j].read_string = candidate_space + 32* island_traverser; //The start of each candidate is aligned properly
//            memcpy(correction_space[island_traverser], read_obj.read_string, 256);
//
//            //Set three MSB bytes to 0 and provide read length and island information there
//            correction_space[island_traverser][63] &= 0x000000ff;
//            correction_space[island_traverser][63] |= (read_obj.read_length << 24) | (read_obj.start_position[j] << 16) | (read_obj.end_position[j] << 8);
//        }
//    }
// return 0;
//
//}
