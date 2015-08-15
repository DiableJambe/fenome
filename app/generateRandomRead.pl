#!/usr/bin/perl

my $readLength = $ARGV[0];

my $read = &generateRandomRead($readLength);

print "$read\n";

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
