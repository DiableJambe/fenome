#!/usr/bin/perl

my $binary = $ARGV[0];

my @array = unpack '(a2)*', $binary;

my $kmerString = "";

foreach $bin (@array) {
    my $charNucleotide = &bin2charNucleotide($bin);

    $kmerString = "$charNucleotide$kmerString";
}

print "$kmerString\n";


sub bin2charNucleotide {
    my $bin = $_[0];

    my $charNucleotide;

    if ($bin =~  /00/) {
        $charNucleotide = 'A';
    }

    if ($bin =~  /01/) {
        $charNucleotide = 'C';
    }

    if ($bin =~  /10/) {
        $charNucleotide = 'G';
    }

    if ($bin =~  /11/) {
        $charNucleotide = 'T';
    }

    return $charNucleotide;
}
