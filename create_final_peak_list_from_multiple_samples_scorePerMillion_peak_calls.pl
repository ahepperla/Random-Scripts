#! /usr/bin/perl -w
use strict;

#Script that uses a greedy algorithm to call a final peak set based on score-per-million calculated peak score. It takes overlapping windows and the one w/ the highest SPM is what is kept as the official, final peak.
#Usage: perl create_final_peak_list_from_multiple_samples_scorePerMillion_peak_calls.pl <out.bed> <file1.bed file2.bed file3.bed ... fileN.bed>

my $outbed = shift;
my $cat_arg = "cat ";

foreach my $files(@ARGV){
	$cat_arg = "$cat_arg $files ";
}
$cat_arg = $cat_arg."> temp_master_bed.bed";

system("$cat_arg");
system("sort -k1,1 -k2,2n temp_master_bed.bed > temp_master_bed_sorted.bed");

open(MASTER, "<temp_master_bed_sorted.bed");
open(OUT, ">$outbed");
my $anchor_region_str = <MASTER>;
chomp $anchor_region_str;
my $best_region_str = $anchor_region_str;
my @anchor_region_arr = split(/\t/, $anchor_region_str);
my @best_region_arr = split(/\t/, $best_region_str);
my $overlapping_counter = 1;
while(<MASTER>){
	chomp $_;
	
	my @cur_region = split(/\t/, $_);
	
	if($cur_region[0] ne $anchor_region_arr[0]){ #if new region is on a different chromosome
		if($overlapping_counter > 1){ #if the current anchor region is alone, dont print out (require at least one overlap, meaning a peak is found in at least 2 samples)
			#print out the current best region and reset variables for new region and chromosome
			print OUT "$best_region_str\n";
			
			$anchor_region_str = $_;
			$best_region_str = $anchor_region_str;
			@anchor_region_arr = split(/\t/, $anchor_region_str);
			@best_region_arr = split(/\t/, $best_region_str);
			$overlapping_counter = 1;
		}
		else{
			#reset variables for new region and chromosome, ignoring the current anchor as it has no overlaps with another sample
			$anchor_region_str = $_;
			$best_region_str = $anchor_region_str;
			@anchor_region_arr = split(/\t/, $anchor_region_str);
			@best_region_arr = split(/\t/, $best_region_str);
			$overlapping_counter = 1;
		}
	}
	elsif($cur_region[1] >= $anchor_region_arr[2]){ #if the new region does not overlap the current anchor region. Not > because the end base in a bed file is not inclusive
		if($overlapping_counter > 1){ #if the current anchor region is alone, dont print out (require at least one overlap, meaning a peak is found in at least 2 samples)
			#print out the current best region and reset variables for new region
			print OUT "$best_region_str\n";
			
			$anchor_region_str = $_;
			$best_region_str = $anchor_region_str;
			@anchor_region_arr = split(/\t/, $anchor_region_str);
			@best_region_arr = split(/\t/, $best_region_str);
			$overlapping_counter = 1;
		}
		else{
			#reset variables for new region, ignoring the current anchor as it has no overlaps with another sample
			$anchor_region_str = $_;
			$best_region_str = $anchor_region_str;
			@anchor_region_arr = split(/\t/, $anchor_region_str);
			@best_region_arr = split(/\t/, $best_region_str);
			$overlapping_counter = 1;
		}
	}
	elsif($cur_region[1] < $anchor_region_arr[2]){ #if the new region start is before or at the anchor region end, then we have an overlap and must compare SPM values to determine best peak. Not <= because the end base in a bed file is not inclusive
		$overlapping_counter++; #update the counter as we have a new overlap
		if($cur_region[4] > $best_region_arr[4]){ #if a higher SPM is found, replace the previous best score region with the current region
			$best_region_str = $_;
			@best_region_arr = split(/\t/, $_);
		}
	}
	else{
		die "Invalid bed file. Error at line $.\n";
	}
}

#print out the final line if there is an overlap
if($overlapping_counter > 1){ #if the current anchor region is alone, dont print out (require at least one overlap, meaning a peak is found in at least 2 samples)
	print OUT "$best_region_str\n";
}
close(MASTER);
close(OUT);
system("rm temp_master_bed.bed");
system("rm temp_master_bed_sorted.bed");