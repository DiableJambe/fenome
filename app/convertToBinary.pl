#!/usr/bin/perl
#

my $fileName = $ARGV[0];

open FILE, "<$fileName";

while (<FILE>) {
    chomp;
    s/#.*//g;   #Comments
    s/\s*//g;   #White spaces
    next if /^\s*$/; #Empty lines
    my $kmer = $_;
    my @kmerSplit = reverse split //, $kmer;

    #Now convert to binary
    my $binary = "";
    foreach $k (@kmerSplit) {
        if ($k =~ /A/) {
            $binary .= "00";
        } 
        if ($k =~ /C/) {
            $binary .= "01";
        }
        if ($k =~ /G/) {
            $binary .= "10";
        }
        if ($k =~ /T/) {
            $binary .= "11";
        }
    }
    print "$binary\n";
}

