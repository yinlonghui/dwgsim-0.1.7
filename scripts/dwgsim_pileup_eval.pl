#!/usr/bin/perl -w

# Copied from SAMtools (http://samtools.sourceforge.net)

# This perl code is very cryptic.  Evaluates the fraction 
# of reads correctly aligned at various mapping quality 
# thresholds.

use strict;
use warnings;
use Getopt::Std;

select STDERR; $| = 1;  # make STDERR unbuffered

&dwgsim_eval;
exit;

sub dwgsim_eval {
	my %opts = (g=>5, n=>0);
	getopts('bpc:gn:', \%opts);
	print_usage() if (@ARGV == 0 && -t STDIN);
	my ($flag, $m, $ctr) = (0, 0, 0);
	my $gap = $opts{g};
	my $bwa = (defined $opts{b}) ? 1 : 0;
	$flag |= 1 if (defined $opts{p});
	$flag |= 2 if (defined $opts{c});
	my $n = 2*$opts{n};
	my @a = ();

	my $prev_read_name = "ZZZ";
	my @reads = ();

	my ($found_correct_1, $found_correct_2, $is_correct_1, $is_correct_2, $found_pair_correct, $is_pair_correct) = (0, 0, 0, 0, 0, 0);

	print STDERR "Analyzing...\nCurrently on:\n0";
	while (<>) {
		$ctr++;
		if(0 == ($ctr % 10000)) {
			print STDERR "\r$ctr";
		}
		next if (/^\@/);
		my @t = split("\t");
		next if (@t < 11);
		my $sam = $_;
		my $cur_read_name = $t[0];

		if($prev_read_name ne $cur_read_name) { # process the read(s)
			die unless (0 == length($prev_read_name) || 0 < scalar(@reads));

			# go through each end
			# want to know
			# 	- is the correct location represented in each end?
			# 	- if so, does the correct location have the best alignment score?
			#   - what's the combined alignment score of the best pair?
			@a = process_reads(\@reads, $flag, $gap, $bwa);
			$found_correct_1 += $a[0];
			$found_correct_2 += $a[1];
			$is_correct_1 += $a[2];
			$is_correct_2 += $a[3];
			$found_pair_correct += $a[4];
			$is_pair_correct += $a[5];

			$prev_read_name = $cur_read_name;
			@reads = ();
			$m++;
		}
		# store the read
		push(@reads, $sam);

		#print STDERR $line if (($flag&1) && !$is_correct && $q > 0);
	}
	@a = process_reads(\@reads, $flag, $gap, $bwa);
	$found_correct_1 += $a[0];
	$found_correct_2 += $a[1];
	$is_correct_1 += $a[2];
	$is_correct_2 += $a[3];
	$found_pair_correct += $a[4];
	$is_pair_correct += $a[5];
	print STDERR "\r$ctr\n";

	printf(STDERR "%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
		$m, $found_correct_1, $found_correct_2, 
		$is_correct_1, $is_correct_2,
		$found_pair_correct,
		$is_pair_correct);

	print STDERR "Analysis complete.\n";
}

sub print_usage {
	print STDERR "Usage: dwgsim_eval.pl [-pcnd] [-g GAP] <in.sam>\n";
	print STDERR "\t\t-p\t\tprint incorrect alignments\n";
	print STDERR "\t\t-c\t\tcolor space alignments\n";
	print STDERR "\t\t-n\tINT\tnumber of raw input paired-end reads\n";
	print STDERR "\t\t-d\tINT\tdivide quality by this factor\n";
	print STDERR "\t\t-i\t\tprint only alignments with indels\n";
	print STDERR "\t\t-b\t\talignments are from BWA\n";
	exit(1);
}

sub swap {
	my ($a, $b) = @_;
	return ($b, $a);
}

sub process_reads {
	my ($reads, $flag, $gap, $bwa) = @_;

	my ($found_correct_1, $found_correct_2, $is_correct_1, $is_correct_2, $found_pair_correct, $is_pair_correct) = (0, 0, 0, 0, 0, 0);
	my ($correct_index_1, $correct_index_2, $max_AS_index_1, $max_AS_index_2, $max_AS_1, $max_AS_2) = (-1, -1, -1, -1, -1000000, -1000000);

	# go through reads
	for(my $i=0;$i<scalar(@$reads);$i++) {
		my $line = $reads->[$i];

		my @t = split(/\t/, $line);
		die if (@t < 11);
		my ($q, $chr, $left, $rght) = ($t[4], $t[2], $t[3], $t[3]);
		# right coordinate
		$_ = $t[5]; s/(\d+)[MDN]/$rght+=$1,'x'/eg;
		--$rght;

		# skip unmapped reads
		next if (($t[1]&0x4) || $chr eq '*');

		# parse read name
		if($t[0] =~ m/^(\S+)_(\d+)_(\d+)_(\d)_(\d)_(\d+):(\d+):(\d+)_(\d+):(\d+):(\d+)_(\S+)/) {
			my ($o_chr, $pos_1, $pos_2, $str_1, $str_2) = ($1, $2, $3, $4, $5);
			my ($n_err_1, $n_sub_1, $n_indel_1, $n_err_2, $n_sub_2, $n_indel_2) = ($6, $7, $8, $9, $10, $11);
			my $end = 2;
			if(($t[1]&0x40)) { # read #1
				$end = 1;
			}

			# check alignment score
			for(my $j=11;$j<scalar(@t);$j++) {
				if($t[$j] =~ m/AS:i:(-?\d+)/) {
					my $AS = $1;
					if(1 == $end) {
						if($max_AS_index_1 == -1 || $max_AS_1 < $AS) {
							$max_AS_index_1 = $i;
							$max_AS_1 = $AS;
						}
					}
					else {
						if($max_AS_index_2 == -1 || $max_AS_2 < $AS) {
							$max_AS_index_2 = $i;
							$max_AS_2 = $AS;
						}
					}
					last;
				}
			}

			if ($o_chr eq $chr) { # same chr
				if ($flag & 2) { # SOLiD
					if(1 == $bwa) {
						# Swap 1 and 2
						($pos_1, $pos_2) = &swap($pos_1, $pos_2);
						($str_1, $str_2) = &swap($str_1, $str_2);
						($n_err_1, $n_err_2) = &swap($n_err_1, $n_err_2);
						($n_sub_1, $n_sub_2) = &swap($n_sub_1, $n_sub_2);
						($n_indel_1, $n_indel_2) = &swap($n_indel_1, $n_indel_2);
					}
				}

				if(1 == $end) { # first read
					if(abs($pos_1 - $left) <= $gap) {
						$found_correct_1=1;
						$correct_index_1 = $i; 
					}
				} else { # second read
					if(abs($pos_2 - $left) <= $gap) {
						$found_correct_2=1;
						$correct_index_1 = $i; 
					}
				}
			}
		} else {
			warn("[dwgsim_eval] read '$t[0]' was not generated by dwgsim?\n");
			next;
		}
	}

	# was the max AS the correct one?
	if(0 < $found_correct_1 && $correct_index_1 == $max_AS_index_1) {
		$is_correct_1=1;
	}
	if(0 < $found_correct_2 && $correct_index_2 == $max_AS_index_2) {
		$is_correct_2=1;
	}

	# check pair ???
	if(0 < $found_correct_1 && 0 < $found_correct_2) {
		$found_pair_correct = 1;
	}
	if(1 == $is_correct_1 && 1 == $is_correct_2) {
		$is_pair_correct = 1;
	}

	return ($found_correct_1, $found_correct_2, $is_correct_1, $is_correct_2, $found_pair_correct, $is_pair_correct);
}
