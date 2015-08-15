#!/usr/bin/perl
my $file = $ARGV[0];

open READ, "<$file";

my $four00Zeroes = "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
my $line;
while ($line = <READ>) {
    chomp($line);
    my @items = split /,/, $line;
    my $bin = `echo $items[0] > /tmp/list; perl convertToBinary.pl /tmp/list`;
    chomp($bin);
    my $startPosition = sprintf("%08b", $items[1]);
    my $endPosition = sprintf("%08b", $items[2]);
    my $readLength = sprintf("%08b", $items[3]);
    my $printLine = "$four00Zeroes$bin$startPosition$endPosition$readLength\n";
    print $printLine;
}

