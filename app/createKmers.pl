#!/usr/bin/perl

#my $read           = &generateRandomRead(101);
my $read           = $ARGV[0];
my $kmerLength     = $ARGV[1];
my @kmerArray      = &extractKmersFromRead($read, $kmerLength);
my @prependedKmers = &prependKmerWithRandomNucleotide($kmerArray[0], 6);
my @subtendedKmers = &subtendKmerWithRandomNucleotide($kmerArray[$#kmerArray], 6);
push @kmerArray, @prependedKmers;
push @kmerArray, @subtendedKmers;

#Add errors to the read - providing alternative KMERs for covering positions on the reads - original read should come out
my $smallErroneousRead   = &createError3PrimeEnd($read, 5);
my $smallErroneousRead   = &createError5PrimeEnd($smallErroneousRead, 5);
my $smallErroneousRead   = &createErrorBetweenReads($smallErroneousRead, 2, 2);
my @kmersOfErroneousRead = &extractKmersFromRead($smallErroneousRead, $kmerLength);
$#prependedKmers         = -1;
$#subtendedKmers         = -1;
@prependedKmers          = &prependKmerWithRandomNucleotide($kmersOfErroneousRead[0], 4);
@subtendedKmers          = &subtendKmerWithRandomNucleotide($kmersOfErroneousRead[$#kmersOfErroneousRead], 4);
push @kmersOfErroneousRead, @prependedKmers;
push @kmersOfErroneousRead, @subtendedKmers;

#Print out results
$" = "\n";
print "#Kmers of Original Read: $read\n";
print "@kmerArray\n\n";
#print "Kmers of similar Read: $smallErroneousRead\n"; 
#print "@kmersOfErroneousRead\n";

#Prepend kmer with random nucleotides
sub prependKmerWithRandomNucleotide {
    my $kmer        = $_[0];
    my $numPrepends = $_[1];

    my @prependedKmers;
    
   my $currentKmer = $kmer;
   foreach (1 .. $numPrepends) {
       $currentKmer = substr $currentKmer, 0, (length $kmer) - 1;
       my $prependNucleotide = &nucleotideValToChar(rand(4) & 3);
       $currentKmer = "$prependNucleotide$currentKmer";
       push @prependedKmers, $currentKmer;
   }

   return @prependedKmers;
}

#Subtend Kmer with RandomNucleotide
sub subtendKmerWithRandomNucleotide {
    my $kmer        = $_[0];
    my $numSubtends = $_[1];

    my @subtendedKmers;
    
    my $currentKmer = $kmer;

    foreach (1 .. $numSubtends) {
       $currentKmer          = substr $currentKmer, 1;
       my $subtendNucleotide = &nucleotideValToChar(rand(4) & 3);
       $currentKmer          = "$currentKmer$subtendNucleotide";
       push @subtendedKmers, $currentKmer;
    }

    return @subtendedKmers;
}

#Extract all Kmers
sub extractKmersFromRead {
    my $read       = $_[0];
    my $kmerLength = $_[1];
    my @kmerArray;

    foreach (0 .. ((length $read) - $kmerLength)) {
        push @kmerArray, substr $read, $_, $kmerLength;
    }

    return @kmerArray;
}


#Generate random read
sub generateRandomRead {
    my $readLength = $_[0];
    my @counter = 1 .. $readLength;
    my @stringArray; $#stringArray = -1;
    my $readString;

    foreach (1 .. $readLength) {
        my $nucleotideValue = &nucleotideValToChar(int(rand(4)));
        push @stringArray, $nucleotideValue;
    }

    $readString = join '', @stringArray;

    return $readString;
}

#Convert Number to Nucleotide
sub nucleotideValToChar {
    my $nucleotideValue = $_[0];
    my $returnVal;
    if ($nucleotideValue == 0) {
        $returnVal = 'A';
    }
    if ($nucleotideValue == 1) {
        $returnVal = 'C';
    }
    if ($nucleotideValue == 2) {
        $returnVal = 'G';
    }
    if ($nucleotideValue == 3) {
        $returnVal = 'T';
    }
    
    return $returnVal;
}

#Insert error at 3 Prime End
sub createError3PrimeEnd {
    my $read = $_[0];
    my $argv = $_[1];

    my @splitRead = split //, $read;
   
    my $lastIndex = $#splitRead;

    my $numErrors;
    if ($argv == 0) {
        $numErrors = int(rand($lastIndex/4)); #Upto a quarter of the read length of errors on one side
    } else {
        $numErrors = $argv;
    }

    my $localIndex = $lastIndex - $numErrors;

    my @newSplitRead;
    @newSplitRead[0 .. $localIndex] = @splitRead[0 .. $localIndex];

    my @counter = $localIndex + 1 .. $#splitRead; 

    foreach $count (@counter) {
        push @newSplitRead, &nucleotideValToChar(int(rand(4)));
    }

    my $returnRead = join '', @newSplitRead;

    return $returnRead;
}

#Insert error at 5-prime end
sub createError5PrimeEnd {
    my $read = $_[0];
    my $argv = $_[1];

    my @splitRead = split //, $read;
   
    my $lastIndex = $#splitRead;

    my $numErrors;
    if ($argv == 0) {
        $numErrors = int(rand($lastIndex/4)); #Upto a quarter of the read length of errors on one side
    } else {
        $numErrors = $argv;
    }

    my @newSplitRead;
    @newSplitRead[0 .. $lastIndex - $numErrors] = @splitRead[$numErrors .. $lastIndex];

    my @counter = 1 .. $numErrors;

    foreach $count (@counter) {
        unshift @newSplitRead, &nucleotideValToChar(int(rand(4)));
    }

    my $returnRead = join '', @newSplitRead;
 
    return $returnRead;
}

#Insert error between islands
sub createErrorBetweenReads {
    my $read  = $_[0];
    my $argv0 = $_[1];
    my $argv1 = $_[2];

    my $stringLength = length $read;

    my $firstHalf = substr $read, 0, ($stringLength + 1)/2;
    my $secondHalf = substr $read, ($stringLength + 1)/2, ($stringLength - 1)/2;

    my $firstHalfNumErrors = 0;
    my $secondHalfNumErrors = 0;

    if (($argv0 != 0) && ($argv1 != 0)) {
        $firstHalfNumErrors = int(rand($argv));
        $secondHalfNumErrors = $argv - $firstHalfNumErrors;
    } else {
        $firstHalfNumErrors = $argv0;
        $secondHalfNumErrors = $argv1;
    }

    my $firstHalfWithError = &createError3PrimeEnd($firstHalf, $firstHalfNumErrors);
    my $secondHalfWithError = &createError5PrimeEnd($secondHalf, $secondHalfNumErrors);

    my $returnRead = "$firstHalfWithError$secondHalfWithError";

    return $returnRead;
}
