#!/usr/bin/perl

my $kmer = $ARGV[0];
my $kmerLength = length $kmer;
my $numExtensions = $ARGV[1];
my @nucleotides = ('A', 'C', 'G', 'T');
my $prepend = $ARGV[2];
&extendRandomKmers($kmer, $prepend, 0, $numExtensions);

sub extendRandomKmers {
    my $kmer = $_[0];
    my $prepend = $_[1];
    my $curExtension = $_[2];
    my $extLimit = $_[3];
    return if ($curExtension >= $extLimit);
    foreach $base (@nucleotides) {
        if ($prepend == 1) {
            my $localKmer = substr $kmer, 0, $kmerLength - 1;
            my $newKmer = "$base$localKmer";
            print "$newKmer\n";
            &extendRandomKmers($newKmer, $prepend, $curExtension + 1, $extLimit);
        } else {
            my $localKmer = substr $kmer, 1, $kmerLength - 1;
            my $newKmer = "$localKmer$base";
            print "$newKmer\n";
            &extendRandomKmers($newKmer, $prepend, $curExtension + 1, $extLimit);
        }
    }
};
