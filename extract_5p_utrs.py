#!/usr/bin/env python3

import argparse
import re
import sys
from collections import defaultdict
from pyfaidx import Fasta


def parse_args():
    p = argparse.ArgumentParser(
        description="Extract 5' UTR sequences for a list of genes using a genome FASTA and Ensembl GTF."
    )
    p.add_argument(
        "--genome-fasta",
        required=True,
        help="Genome FASTA file (indexed or indexable by pyfaidx).",
    )
    p.add_argument(
        "--gtf",
        required=True,
        help="Ensembl GTF annotation file.",
    )
    p.add_argument(
        "--gene-list-tsv",
        required=True,
        help="2-column TSV: col1 = gene_id.version, col2 = gene_symbol.",
    )
    p.add_argument(
        "--out-fasta",
        required=True,
        help="Output FASTA file for 5' UTR sequences.",
    )
    return p.parse_args()


def infer_chrom_mapper(genome, gtf_path, max_lines=2000):
    """
    Infer how to map GTF chromosome names to FASTA names.

    Returns:
        chrom_mapper: function(chrom_from_gtf) -> chrom_for_fasta

    Strategy:
      1. Collect some chromosome names from GTF.
      2. Check:
         - direct match (gtf chrom in fasta keys)
         - 'chr' + gtf chrom in fasta keys
         - strip 'chr' from fasta keys matches gtf chrom
      3. If none match, exit with error.
    """
    fa_chroms = set(genome.keys())
    gtf_chroms = set()

    with open(gtf_path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            parts = line.split("\t", 1)
            if len(parts) < 2:
                continue
            chrom = parts[0].strip()
            if not chrom:
                continue
            gtf_chroms.add(chrom)
            if len(gtf_chroms) >= max_lines:
                break

    if not gtf_chroms:
        sys.exit("Error: No chromosome names found in GTF. Is the file empty or malformed?")

    # Case 1: direct match
    if all(c in fa_chroms for c in gtf_chroms):
        sys.stderr.write("Chromosome mapping: using GTF names as-is.\n")
        return lambda c: c

    # Case 2: prepend 'chr'
    if all(("chr" + c) in fa_chroms for c in gtf_chroms):
        sys.stderr.write("Chromosome mapping: using 'chr' + GTF chromosome names.\n")
        return lambda c: "chr" + c

    # Case 3: strip 'chr' from FASTA names
    stripped_map = {(c[3:] if c.startswith("chr") else c): c for c in fa_chroms}
    if all(c in stripped_map for c in gtf_chroms):
        sys.stderr.write("Chromosome mapping: stripping 'chr' from FASTA names.\n")
        return lambda c: stripped_map[c]

    sys.stderr.write("FASTA chroms: {}\n".format(sorted(list(fa_chroms))[:10]))
    sys.stderr.write("GTF chroms:   {}\n".format(sorted(list(gtf_chroms))[:10]))
    sys.exit(
        "Error: Could not reconcile chromosome names between FASTA and GTF "
        "(e.g., '2' vs 'chr2'). Please fix your inputs or add custom logic."
    )


def build_five_prime_utr_index(gtf_path):
    """
    Index five_prime_utr Ensembl_canonical entries by gene_id.

    Returns:
        dict[gene_id] -> list of entries
        each entry is a dict with chrom, start, end, strand, attrs
    """
    idx = defaultdict(list)
    attr_re = re.compile(r'(\S+) "([^"]+)"')

    with open(gtf_path) as f:
        for line in f:
            if line.startswith("#"):
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 9:
                continue

            chrom, source, feature, start, end, score, strand, frame, attrs = cols

            # Only 5'UTR and Ensembl canonical entries
            if feature != "five_prime_utr":
                continue
            if 'tag "Ensembl_canonical"' not in attrs:
                continue

            # Parse attributes into a dict
            attr_dict = dict(attr_re.findall(attrs))
            gene_id = attr_dict.get("gene_id")
            gene_version = attr_dict.get("gene_version")

            if not gene_id or not gene_version:
                continue

            idx[gene_id].append(
                {
                    "chrom": chrom,
                    "start": int(start),
                    "end": int(end),
                    "strand": strand,
                    "attrs": attr_dict,
                }
            )

    return idx


def reverse_complement(seq):
    seq = seq.upper()
    complement = str.maketrans("ACGTN", "TGCAN")
    return seq.translate(complement)[::-1]


def wrap_fasta(sequence, width=60):
    return "\n".join(sequence[i : i + width] for i in range(0, len(sequence), width))


def main():
    args = parse_args()

    # Load genome with pyfaidx
    try:
        genome = Fasta(args.genome_fasta)
    except Exception as e:
        sys.exit(f"Error loading genome FASTA with pyfaidx: {e}")

    # Infer chromosome mapping between GTF and FASTA
    chrom_mapper = infer_chrom_mapper(genome, args.gtf)

    # Build 5' UTR index from GTF
    sys.stderr.write("Building 5' UTR index from GTF...\n")
    utr_index = build_five_prime_utr_index(args.gtf)
    sys.stderr.write(f"Indexed 5' UTRs for {len(utr_index)} genes.\n")

    # Read gene list and write output FASTA
    n_found = 0
    n_missing = 0

    with open(args.gene_list_tsv) as gene_fh, open(args.out_fasta, "w") as out_fh:
        for line in gene_fh:
            line = line.rstrip()
            if not line or line.startswith("#"):
                continue
            
            parts = line.split("\t")
            if len(parts) < 2:
                sys.stderr.write(f"Skipping line (not enough columns): {line}\n")
                continue

            gene_id_ver = parts[0]  # e.g., ENSMUSG00000011179.9
            gene_symbol = parts[1]

            # Split gene_id and version (we only use gene_id as index key)
            gene_id = gene_id_ver.split(".")[0]

            utr_entries = utr_index.get(gene_id)
            if not utr_entries:
                n_missing += 1
                sys.stderr.write(f"Warning: no 5' UTR found for gene_id {gene_id}\n")
                continue

            # Sort by genomic start; RC will fix orientation for '-' strand
            utr_entries = sorted(utr_entries, key=lambda r: r["start"])

            seq_fragments = []
            failed = False
            for rec in utr_entries:
                chrom = chrom_mapper(rec["chrom"])
                start = rec["start"]
                end = rec["end"]
                try:
                    seq_fragments.append(str(genome.get_seq(chrom, start, end)))
                except KeyError:
                    sys.stderr.write(
                        f"Error: chromosome {chrom} not in FASTA (gene {gene_id}). Skipping.\n"
                    )
                    failed = True
                    break
            if failed or not seq_fragments:
                continue

            utr_seq = "".join(seq_fragments).upper()
            strand = utr_entries[0]["strand"]
            if strand == "-":
                utr_seq = reverse_complement(utr_seq)

            header = f">{gene_id}_{gene_symbol}_5p_UTR"
            out_fh.write(header + "\n")
            out_fh.write(wrap_fasta(utr_seq) + "\n")
            n_found += 1

    sys.stderr.write(f"Done. Wrote 5' UTR sequences for {n_found} genes.\n")
    if n_missing:
        sys.stderr.write(f"Missing 5' UTRs for {n_missing} genes (see warnings above).\n")


if __name__ == "__main__":
    main()
