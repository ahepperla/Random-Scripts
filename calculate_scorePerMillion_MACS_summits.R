#script takes in a MACS2 summit file and converts it to a TCGA-like score-per-million bed file (summit +-250bp)
args = commandArgs(TRUE)

peaks = read.table(args[1], sep="\t")
peaks.total.score = sum(peaks[,5])

peaks[,5] = peaks[,5]/(peaks.total.score/1000000)
peaks[,1] = peaks[,1]-250
peaks[,2] = peaks[,2]+250
peaks[,6] = "+"

out_basename = gsub("_summits.bed","", args[1], fixed=TRUE)

write.out(peaks, file=paste0(out_basename,"_summit_plusMinus250_scorePerMillion.bed"), row.names=F, col.names=F, sep="\t", quote=F)
write.out(peaks[peaks[,5] >= 3,], file=paste0(out_basename,"_summit_plusMinus250_scorePerMillion_greaterLog3SPM.bed"), row.names=F, col.names=F, sep="\t", quote=F)
write.out(peaks[peaks[,5] >= 5,], file=paste0(out_basename,"_summit_plusMinus250_scorePerMillion_greaterLog5SPM.bed"), row.names=F, col.names=F, sep="\t", quote=F)
