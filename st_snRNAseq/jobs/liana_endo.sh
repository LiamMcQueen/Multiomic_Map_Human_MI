#!/bin/bash
#PBS -l nodes=1:ppn=16
#PBS -l walltime=30:00:00
#PBS -l mem=150gb
#PBS -S /bin/bash
#PBS -N visium_mrkr_estimation
#PBS -o /beegfs/work/hd_wh241/MI_revisions/analysis/jobs/liana_endo.out
#PBS -e /beegfs/work/hd_wh241/MI_revisions/analysis/jobs/liana_endo.err
#PBS -q smp
#PBS -m bea
#PBS -M roramirezf@uni-heidelberg.de

source ~/.bashrc;
conda activate liana;
cd /beegfs/work/hd_wh241/MI_revisions;

$CONDA_PREFIX/bin/Rscript ./analysis/14_cellcomms/run_liana_adv.R \
        --data_path "/beegfs/work/hd_wh241/MI_revisions/processed_snrnaseq/cell_states/integrated_rnasamples_ann_wstates.rds" \
        --cell_type_list "CM,vSMCs,Fib,PC" \
	--cell_state_list "Endo" \
        --out_file "/beegfs/work/hd_wh241/MI_revisions/results/cell_comms/liana_Endo.rds";