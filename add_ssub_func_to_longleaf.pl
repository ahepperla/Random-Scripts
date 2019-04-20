#! /usr/bin/perl -w
use strict;

#Usage: perl add_ssub_func_to_longleaf.pl </place/for/log/directory> <email> 
#Example: perl add_ssub_func_to_longleaf.pl /proj/dllab/hepperla hepperla@unc.edu
#
#Script that adds Jeremy Simon's ssub function to your environment for UNC's Longleaf HPCC. It mimics the old LSF bsub function and allows you to submit a job and receive an email upon completion detailing the job output and usage stats."

=begin comment
#########################################################################################
#########################################################################################
The basic idea is that where you'd normally run a one-off submission like:
sbatch [...] --partition=general --wrap="stuff"

you would instead run
ssub [...] --partition=general --notify=ON --wrap=\"stuff with \'escaped\' special characters\"

or for the quieter option (aka no email sent, but logfile still saved):
ssub [...] --partition=general --notify=OFF --wrap=\"stuff with \'escaped\' special characters\"

or if you just want to use defaults (notify=ON, partition=general)
ssub [...] --wrap=\"stuff with \'escaped\' special characters\"


The --partition and --notify are now both *optional* parameters, and it can be a " " or "=" that separates them from their set value. --notify will default to ON, and --partition will default to general. 

The general idea behind the code is to capture date and time (to the millisecond), create a log file named by that timestamp, dump the command issued and other things to that logfile, then run sbatch pointing slurm to append any output to that file. Then, as soon as the sbatch job finishes, run an sacct on that job ID to get memory usage and runtime info, dumping those results to the bottom of the same log file. Then if --notify=ON, it will send the contents of that log file in an email to you. 


If you run just a single job like the basic mockup above, you'll get just the job ID printed to the screen upon submission. 

If you want to submit a sequence of jobs, each dependent on the previous, you would create a script (e.g. 'nano script.sh') that would look something like:

source ~/.bashrc                      ## these shell scripts apparently don't load the bashrc unless it's some kind of interactive mode. this will make sure you don't get a "ssub: command not found" error.
jid1=$(ssub --wrap=\"stuff with \'escaped\' special characters\")
jid2=$(ssub -d afterok:$jid1 --wrap=\"stuff with \'escaped\' special characters\")
jid3=$(ssub -d afterok:$jid2 --wrap=\"stuff with \'escaped\' special characters\")
echo $jid1,$jid2,$jid3
...

then execute with a simple "sh script.sh". If all goes well, the only output to the command-line you'll get will be a comma-separated list of the job IDs spawned for this sequence, but you'll get fancy emails as each job finishes/exits
#########################################################################################
#########################################################################################
=end comment
=cut

my $log_dir_destination = shift;
my $email = shift;

my $ssub = `grep ssub ~/.bashrc`;
if($ssub ne ""){
        die "You already have some ssub in your ~/.bashrc file. Please remove it before continuing.\n";
}

my $id = `id`;
my @id = split(/\s/, $id);
my @onyen = split(/\(/, $id[0]);
$onyen[1] =~ s/\)//;
my $pine_junk = "/pine/scr/".substr($onyen[1], 0, 1)."/".substr($onyen[1], 1, 1)."/".$onyen[1]."/junk"; 
system("mkdir $pine_junk");
system("mkdir $log_dir_destination/SLURM_logs/");

open(OUT, ">$pine_junk/ssub.txt");
my $ssub_command = "export SLURMLOGLOC=$log_dir_destination/SLURM_logs/

function ssub {
        day=\$(date '+%Y/%m/%d')
        mkdir -p \$SLURMLOGLOC\$day
        log=\$(date '+%Y%m%d_%H-%M-%S-%3N')
        cmd=\"sbatch -o \$SLURMLOGLOC\$day/\$log -e \$SLURMLOGLOC/\$day/\$log --time=10-12 --open-mode=append \$*\"
        notify=\$(echo \$cmd | sed -nE 's/.+notify.(\\w+).+/\\1/p')
        if ! { [ \"\$notify\" = \"ON\" ] || [ \"\$notify\" = \"OFF\" ]; }; then
                notify=\"ON\"
        fi

            cmd2=\$(echo \$cmd | sed -E 's/--notify\\=\\w+ //')

        echo -e \"Your job looked like:\\n###################################################################################\\n\" \>\> \$SLURMLOGLOC\$day/\$log
        echo \$cmd2 \>\> \$SLURMLOGLOC/\$day/\$log
        echo -e \"\\n###################################################################################\\n\" \>\> \$SLURMLOGLOC\$day/\$log
        jobID=\"\$(eval \$cmd2 | cut -f 4 -d ' ')\"

        if [ \"\$notify\" = \"ON\" ]; then
                memory=\"sbatch -o $pine_junk/\$log -d afterany:\$jobID --partition general --wrap=\\\"echo -e '\\n\\nJob runtime metrics:\\n###################################################################################\\n' \>\> \$SLURMLOGLOC\$day/\$log;\
                sacct --format=\"JobID,JobName,Partition,AllocCPUS,Submit,Elapsed,State,CPUTime,MaxRSS\" --units=G -j \$jobID \>\> \$SLURMLOGLOC\$day/\$log;\
                echo -e '\\n###################################################################################\\n' \>\> \$SLURMLOGLOC\$day/\$log;\
                echo 'Subject: SLURM job \$jobID' | cat - \$SLURMLOGLOC\$day/\$log | sendmail $email\\\"\"
        elif [ \"\$notify\" = \"OFF\" ]; then
                memory=\"sbatch -o $pine_junk/\$log -d afterany:\$jobID --partition general --wrap=\\\"echo -e '\\n\\nJob runtime metrics:\\n###################################################################################\\n' \>\> \$SLURMLOGLOC\$day/\$log;\
                sacct --format=\"JobID,JobName,Partition,AllocCPUS,Submit,Elapsed,State,CPUTime,MaxRSS\" --units=G -j \$jobID \>\> \$SLURMLOGLOC\$day/\$log;\
                echo -e '\\n###################################################################################\\n' \>\> \$SLURMLOGLOC\$day/\$log\\\"\"
        fi
            memoryID=\"\$(eval \$memory | cut -f 4 -d ' ')\"

        queue=\$(echo \$cmd2 | sed -nE 's/.+partition.(\\w+).+/\\1/p')
        if [ \"\$partition\" = \"\" ]; then
                queue=\"general\"
        fi

            echo \"Job \<\$jobID\> submitted to partition \<\$queue\>\" \>\> \$SLURMLOGLOC\$day/\$log

        if [ \$notify = \"ON\" ]; then
                echo -e \"Job email notification enabled\\n\" \>\> \$SLURMLOGLOC\$day/\$log
        elif [ \$notify = \"OFF\" ]; then
                echo -e \"Job email notification disabled\\n\" \>\> \$SLURMLOGLOC\$day/\$log
        fi

            echo \"\$jobID\"
        wd=\$(pwd)
        echo -e \"Current Working Directory: \$wd\\n\\n\" \>\> \$SLURMLOGLOC\$day/\$log
        echo -e \"The output (if any) follows:\\n\" \>\> \$SLURMLOGLOC\$day/\$log
}
";
print OUT $ssub_command;
close(OUT);

my $cat_command = `cat $pine_junk/ssub.txt >> ~/.bashrc`;
