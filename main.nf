#!/usr/bin/env nextflow
nextflow.enable.dsl=2

/*
========================================================================================
                         nf-core/scflow
========================================================================================
 nf-core/scflow Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/scflow
----------------------------------------------------------------------------------------
*/

include { getSoftwareName;initOptions;getPathFromList;saveFiles } from './modules/local/process/functions.nf' 
params.options = [:]

def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/scflow --input "refs/Manifest.txt" --samplesheet "refs/SampleSheet.tsv" -c "conf/scflow_params.config"

    Mandatory arguments:
      --input [file]                Path to Manifest.txt file (must be surrounded with quotes)
      --samplesheet [file]          Path to SampleSheet.tsv file (must be surrounded with quotes)
      -profile [str]                Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, test, awsbatch, <institute> and more

    References                        If not specified in the configuration file or you wish to overwrite any of the references
      --ensembl_mappings [file]       Path to ensembl_mappings file
      --celltype_mappings [file]      Path to manual cell-type mappings file
      --ctd_path [file]               Path to the zip file containing .ctd files for celltype annotation
      --reddim_genes_yml [file]       Path to a file containing genes of interest for expression plotting

    Other options:
      --outdir [file]                 The output directory where the results will be saved
      --email [email]                 Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail [email]         Same as --email, except only send mail if the workflow is not successful
      -name [str]                     Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic

    AWSBatch options:
      --awsqueue [str]                The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion [str]               The AWS Region for your AWS Batch job to run on
      --awscli [str]                  Path to the AWS CLI tool
    """.stripIndent()
}
log.info Headers.nf_core(workflow, params.monochrome_logs)

////////////////////////////////////////////////////
/* --               PRINT HELP                 -- */
////////////////////////////////////////////////////+
def json_schema = "$projectDir/nextflow_schema.json"
if (params.help) {
    def command = "nextflow run nf-core/scflow --input '*_R{1,2}.fastq.gz' -profile docker"
    log.info NfcoreSchema.params_help(workflow, params, json_schema, command)
    exit 0
}

////////////////////////////////////////////////////
/* --         VALIDATE PARAMETERS              -- */
////////////////////////////////////////////////////+
if (params.validate_params) {
    NfcoreSchema.validateParameters(params, json_schema, log)
}

////////////////////////////////////////////////////
/* --     Collect configuration parameters     -- */
////////////////////////////////////////////////////

// Has the run name been specified by the user?
// this has the bonus effect of catching both -name and --name
/*
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}
*/

// Check AWS batch settings
if (workflow.profile.contains('awsbatch')) {
    // AWSBatch sanity checking
    if (!params.awsqueue || !params.awsregion) exit 1, 'Specify correct --awsqueue and --awsregion parameters on AWSBatch!'
    // Check outdir paths to be S3 buckets if running on AWSBatch
    // related: https://github.com/nextflow-io/nextflow/issues/813
    if (!params.outdir.startsWith('s3:')) exit 1, 'Outdir not on S3 - specify S3 Bucket to run on AWSBatch!'
    // Prevent trace files to be stored on S3 since S3 does not support rolling files.
    if (params.tracedir.startsWith('s3:')) exit 1, 'Specify a local tracedir or run without trace! S3 cannot be used for tracefiles.'
}

/*
 * Create a channel for input read files
 */
 if (params.input) { ch_input = file(params.input, checkIfExists: true) }
 if (params.samplesheet) { ch_samplesheet = file(params.samplesheet, checkIfExists: true) }
 if (params.samplesheet) { ch_samplesheet2 = file(params.samplesheet, checkIfExists: true) } // copy for qc
 if (params.ctd_path) { ch_ctd_path = file(params.ctd_path, checkIfExists: true) }
 if (params.celltype_mappings) { ch_celltype_mappings = file(params.celltype_mappings, checkIfExists: false) }
 if (params.ensembl_mappings) { ch_ensembl_mappings = file(params.ensembl_mappings, checkIfExists: false) }
 if (params.ensembl_mappings) { ch_ensembl_mappings2 = file(params.ensembl_mappings, checkIfExists: false) }
 if (params.ensembl_mappings) { ch_ensembl_mappings3 = file(params.ensembl_mappings, checkIfExists: false) }
 if (params.reddim_genes_yml) { ch_reddim_genes_yml = file(params.reddim_genes_yml, checkIfExists: true) }

////////////////////////////////////////////////////
/* --         PRINT PARAMETER SUMMARY          -- */
////////////////////////////////////////////////////
log.info NfcoreSchema.params_summary_log(workflow, params, json_schema)

// Header log info
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
//summary['Run Name']       = custom_runName ?: workflow.runName
summary['Run Name']         = workflow.runName
summary['Input']            = params.input
summary['SampleSheet']      = params.samplesheet
summary['Run EmptyDrops']   = params.amb_find_cells ? "Yes" : "No"
summary['Find Singlets']    = params.mult_find_singlets ? "Yes ($params.mult_singlets_method)" : 'No'
summary['Dimension Reds.']  = params.reddim_reduction_methods
summary['Clustering Input'] = params.clust_reduction_method
summary['DGE Method']       = params.dge_de_method == "MASTZLM" ? "$params.dge_de_method ($params.dge_mast_method)": "$params.dge_de_method"
summary['DGE Dependent Var']= params.dge_dependent_var
summary['DGE Ref Class']    = params.dge_ref_class
summary['DGE Confound Vars']= params.dge_confounding_vars
summary['Run Name']         = workflow.runName

summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile.contains('awsbatch')) {
    summary['AWS Region']   = params.awsregion
    summary['AWS Queue']    = params.awsqueue
    summary['AWS CLI']      = params.awscli
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Profile Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Profile Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config Profile URL']         = params.config_profile_url
summary['Config Files'] = workflow.configFiles.join(', ')
if (params.email || params.email_on_fail) {
    summary['E-mail Address']    = params.email
    summary['E-mail on failure'] = params.email_on_fail
    summary['MultiQC maxsize']   = params.max_multiqc_email_size
}

// Check the hostnames against configured profiles
checkHostname()

Channel.from(summary.collect{ [it.key, it.value] })
    .map { k,v -> "<dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }
    .reduce { a, b -> return [a, b].join("\n            ") }
    .map { x -> """
    id: 'nf-core-scflow-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/scflow Workflow Summary'
    section_href: 'https://github.com/nf-core/scflow'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
            $x
        </dl>
    """.stripIndent() }
    .set { ch_workflow_summary }

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: params.publish_dir_mode,
        saveAs: { filename ->
                      if (filename.indexOf('.csv') > 0) filename
                      else null
        }

    output:
    file 'software_versions_mqc.yaml' into ch_software_versions_yaml
    file 'software_versions.csv'

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    R --version > v_R.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

////////////////////////////////////////////////////
/* --    IMPORT LOCAL MODULES/SUBWORKFLOWS     -- */
////////////////////////////////////////////////////

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()

def scflow_checkinputs_options         = modules['scflow_checkinputs']
scflow_checkinputs_options.args        = ''

def scflow_qc_options                  = modules['scflow_qc']
scflow_qc_options.args                 = 
    "--key_colname ${params.qc_key_colname} \
    --factor_vars ${params.qc_factor_vars} \
    --min_library_size ${params.qc_min_library_size} \
    --max_library_size ${params.qc_max_library_size} \
    --min_features ${params.qc_min_features} \
    --max_features ${params.qc_max_features} \
    --max_mito ${params.qc_max_mito} \
    --min_ribo ${params.qc_min_ribo} \
    --max_ribo ${params.qc_max_ribo} \
    --min_counts ${params.qc_min_counts} \
    --min_cells ${params.qc_min_cells} \
    --drop_unmapped ${params.qc_drop_unmapped} \
    --drop_mito ${params.qc_drop_mito} \
    --drop_ribo ${params.qc_drop_ribo} \
    --nmads ${params.qc_nmads} \
    --find_singlets ${params.mult_find_singlets} \
    --singlets_method ${params.mult_singlets_method} \
    --vars_to_regress_out ${params.mult_vars_to_regress_out} \
    --pca_dims ${params.mult_pca_dims} \
    --var_features ${params.mult_var_features} \
    --doublet_rate ${params.mult_doublet_rate} \
    --dpk ${params.mult_dpk} \
    --pK ${params.mult_pK} \
    --find_cells ${params.amb_find_cells} \
    --lower ${params.amb_lower} \
    --retain ${params.amb_retain} \
    --alpha_cutoff ${params.amb_alpha_cutoff} \
    --niters ${params.amb_niters}  \
    --expect_cells ${params.amb_expect_cells} \
    --species ${params.species} "

def scflow_mergeqctables_options  = modules['scflow_mergeqctables']
scflow_mergeqctables_options.args = ''

def scflow_merge_options             = modules['scflow_merge']
scflow_merge_options.args            =
    "--unique_id_var ${params.qc_key_colname} \
    --plot_vars ${params.merge_plot_vars} \
    --facet_vars ${params.merge_facet_vars} \
    --outlier_vars ${params.merge_outlier_vars} \
    --species ${params.species}"

def scflow_integrate_options         = modules['scflow_integrate']
scflow_integrate_options.args        =
    "--method ${params.integ_method} \
    --unique_id_var ${params.integ_unique_id_var} \
    --take_gene_union ${params.integ_take_gene_union} \
    --remove_missing ${params.integ_remove_missing} \
    --num_genes ${params.integ_num_genes} \
    --combine ${params.integ_combine} \
    --keep_unique ${params.integ_keep_unique} \
    --capitalize ${params.integ_capitalize} \
    --use_cols ${params.integ_use_cols} \
    --k ${params.integ_k} \
    --lambda ${params.integ_lambda} \
    --thresh ${params.integ_thresh} \
    --max_iters ${params.integ_max_iters} \
    --nrep ${params.integ_nrep} \
    --rand_seed ${params.integ_rand_seed} \
    --knn_k ${params.integ_knn_k} \
    --k2 ${params.integ_k2} \
    --prune_thresh ${params.integ_prune_thresh} \
    --ref_dataset ${params.integ_ref_dataset} \
    --min_cells ${params.integ_min_cells} \
    --quantiles ${params.integ_quantiles} \
    --nstart ${params.integ_nstart} \
    --resolution ${params.integ_resolution} \
    --dims_use ${params.integ_dims_use} \
    --dist_use ${params.integ_dist_use} \
    --center ${params.integ_center} \
    --small_clust_thresh ${params.integ_small_clust_thresh} \
    --reddimplot_pointsize ${params.reddimplot_pointsize} \
    --reddimplot_alpha ${params.reddimplot_alpha}"

def scflow_reducedims_options        = modules['scflow_reducedims']
scflow_reducedims_options.args       = 
    "--input_reduced_dim ${params.reddim_input_reduced_dim} \
    --reduction_methods ${params.reddim_reduction_methods} \
    --vars_to_regress_out ${params.reddim_vars_to_regress_out} \
    --pca_dims ${params.reddim_umap_pca_dims} \
    --n_neighbors ${params.reddim_umap_n_neighbors} \
    --n_components ${params.reddim_umap_n_components} \
    --init ${params.reddim_umap_init} \
    --metric ${params.reddim_umap_metric} \
    --n_epochs ${params.reddim_umap_n_epochs} \
    --learning_rate ${params.reddim_umap_learning_rate} \
    --min_dist ${params.reddim_umap_min_dist} \
    --spread ${params.reddim_umap_spread} \
    --set_op_mix_ratio ${params.reddim_umap_set_op_mix_ratio} \
    --local_connectivity ${params.reddim_umap_local_connectivity} \
    --repulsion_strength ${params.reddim_umap_repulsion_strength} \
    --negative_sample_rate ${params.reddim_umap_negative_sample_rate} \
    --fast_sgd ${params.reddim_umap_fast_sgd} \
    --dims ${params.reddim_tsne_dims} \
    --initial_dims ${params.reddim_tsne_initial_dims} \
    --perplexity ${params.reddim_tsne_perplexity} \
    --theta ${params.reddim_tsne_theta} \
    --stop_lying_iter ${params.reddim_tsne_stop_lying_iter} \
    --mom_switch_iter ${params.reddim_tsne_mom_switch_iter} \
    --max_iter ${params.reddim_tsne_max_iter} \
    --pca_center ${params.reddim_tsne_pca_center} \
    --pca_scale ${params.reddim_tsne_pca_scale} \
    --normalize ${params.reddim_tsne_normalize} \
    --momentum ${params.reddim_tsne_momentum} \
    --final_momentum ${params.reddim_tsne_final_momentum} \
    --eta ${params.reddim_tsne_eta} \
    --exaggeration_factor ${params.reddim_tsne_exaggeration_factor}"

def scflow_cluster_options          = modules['scflow_cluster']
scflow_cluster_options.args         =
    "--cluster_method ${params.clust_cluster_method} \
    --reduction_method ${params.clust_reduction_method} \
    --res ${params.clust_res} \
    --k ${params.clust_k} \
    --louvain_iter ${params.clust_louvain_iter}"

def scflow_reportintegrated_options  = modules['scflow_reportintegrated']
scflow_reportintegrated_options.args =
   "--categorical_covariates ${params.integ_categorical_covariates} \
    --input_reduced_dim ${params.integ_input_reduced_dim} \
    --reddimplot_pointsize ${params.reddimplot_pointsize} \
    --reddimplot_alpha ${params.reddimplot_alpha}"


def scflow_mapcelltypes_options      = modules['scflow_mapcelltypes']
scflow_mapcelltypes_options.args     =
    "--clusters_colname ${params.cta_clusters_colname} \
    --cells_to_sample ${params.cta_cells_to_sample} \
    --species ${params.species} \
    --reddimplot_pointsize ${params.reddimplot_pointsize} \
    --reddimplot_alpha ${params.reddimplot_alpha}"

def scflow_finalize_options          = modules['scflow_finalize']
scflow_finalize_options.args         =
    "--clusters_colname ${params.cta_clusters_colname} \
     --celltype_var ${params.cta_celltype_var} \
     --unique_id_var ${params.cta_unique_id_var} \
     --facet_vars ${params.cta_facet_vars} \
     --input_reduced_dim ${params.clust_reduction_method} \
     --metric_vars ${params.cta_metric_vars}"

def scflow_plotreddimgenes_options          = modules['scflow_plotreddimgenes']
scflow_plotreddimgenes_options.args          =
    "--reduction_methods ${params.plotreddim_reduction_methods} \
    --reddimplot_pointsize ${params.reddimplot_pointsize} \
    --reddimplot_alpha ${params.reddimplot_alpha}"


def scflow_dge_options               = modules['scflow_dge']
scflow_dge_options.args              =
    "--mast_method ${params.dge_mast_method} \
    --min_counts ${params.dge_min_counts} \
    --min_cells_pc ${params.dge_min_cells_pc} \
    --rescale_numerics ${params.dge_rescale_numerics} \
    --force_run ${params.dge_force_run} \
    --pseudobulk ${params.dge_pseudobulk} \
    --celltype_var ${params.dge_celltype_var} \
    --sample_var ${params.dge_sample_var} \
    --dependent_var ${params.dge_dependent_var} \
    --ref_class ${params.dge_ref_class} \
    --confounding_vars ${params.dge_confounding_vars} \
    --random_effects_var ${params.dge_random_effects_var} \
    --pval_cutoff ${params.dge_pval_cutoff} \
    --fc_threshold ${params.dge_fc_threshold} \
    --species ${params.species} \
    --max_cores ${params.dge_max_cores}"

def scflow_ipa_options               = modules['scflow_ipa']
scflow_ipa_options.args              =
    "--enrichment_tool ${params.ipa_enrichment_tool} \
    --enrichment_method ${params.ipa_enrichment_method} \
    --enrichment_database ${params.ipa_enrichment_database}"

def scflow_dirichlet_options         = modules['scflow_dirichlet']
scflow_dirichlet_options.args = 
    "--unique_id_var ${params.dirich_unique_id_var} \
    --celltype_var ${params.dirich_celltype_var} \
    --dependent_var ${params.dirich_dependent_var} \
    --ref_class ${params.dirich_ref_class} \
    --var_order ${params.dirich_var_order}"


include { SCFLOW_CHECKINPUTS         } from './modules/local/process/scflow/checkinputs'       addParams( options: scflow_checkinputs_options       ) 
include { SCFLOW_QC                  } from './modules/local/process/scflow/qc'                addParams( options: scflow_qc_options                )
include { SCFLOW_MERGEQCTABLES       } from './modules/local/process/scflow/mergeqctables'     addParams( options: scflow_mergeqctables_options  )
include { SCFLOW_MERGE               } from './modules/local/process/scflow/merge'             addParams( options: scflow_merge_options             )
include { SCFLOW_INTEGRATE           } from './modules/local/process/scflow/integrate'         addParams( options: scflow_integrate_options         )
include { SCFLOW_REDUCEDIMS          } from './modules/local/process/scflow/reducedims'        addParams( options: scflow_reducedims_options        )
include { SCFLOW_CLUSTER             } from './modules/local/process/scflow/cluster'           addParams( options: scflow_cluster_options           )
include { SCFLOW_REPORTINTEGRATED    } from './modules/local/process/scflow/reportintegrated'  addParams( options: scflow_reportintegrated_options  )
include { SCFLOW_MAPCELLTYPES        } from './modules/local/process/scflow/mapcelltypes'      addParams( options: scflow_mapcelltypes_options      )
include { SCFLOW_FINALIZE            } from './modules/local/process/scflow/finalize'          addParams( options: scflow_finalize_options          )
include { SCFLOW_PLOTREDDIMGENES     } from './modules/local/process/scflow/plotreddimgenes'   addParams( options: scflow_plotreddimgenes_options   )
include { SCFLOW_DGE                 } from './modules/local/process/scflow/dge'               addParams( options: scflow_dge_options               )
include { SCFLOW_IPA                 } from './modules/local/process/scflow/ipa'               addParams( options: scflow_ipa_options               )
include { SCFLOW_DIRICHLET           } from './modules/local/process/scflow/dirichlet'         addParams( options: scflow_dirichlet_options         )

workflow {  
    
  main:
    SCFLOW_CHECKINPUTS ( 
        ch_input, 
        ch_samplesheet
    )

    SCFLOW_QC ( 
        SCFLOW_CHECKINPUTS.out.checked_input.splitCsv(
            header:['key', 'filepath'], 
            skip: 1, sep: '\t'
            )
        .map { row -> tuple(row.key, row.filepath) }, 
        ch_samplesheet2, 
        ch_ensembl_mappings
    )
    
    SCFLOW_MERGEQCTABLES ( 
        SCFLOW_QC.out.qc_summary.collect() 
    )
    
    SCFLOW_MERGE ( 
        SCFLOW_QC.out.qc_sce.collect(), 
        ch_ensembl_mappings2 
    )

    SCFLOW_INTEGRATE ( 
        SCFLOW_MERGE.out.merged_sce 
    )


    SCFLOW_REDUCEDIMS ( 
        SCFLOW_INTEGRATE.out.integrated_sce 
    )
    
    SCFLOW_CLUSTER ( 
        SCFLOW_REDUCEDIMS.out.reddim_sce 
    )

    SCFLOW_REPORTINTEGRATED (
        SCFLOW_CLUSTER.out.clustered_sce
    )

    SCFLOW_MAPCELLTYPES ( 
        SCFLOW_CLUSTER.out.clustered_sce, 
        ch_ctd_path 
    )

    SCFLOW_FINALIZE ( 
        SCFLOW_MAPCELLTYPES.out.celltype_mapped_sce, 
        ch_celltype_mappings 
    )

    SCFLOW_DGE ( 
        SCFLOW_FINALIZE.out.final_sce, 
        params.dge_de_method, 
        SCFLOW_FINALIZE.out.celltypes.splitCsv (
            header:['celltype', 'n_cells'], skip: 1, sep: '\t'
        )
        .map { row -> tuple(row.celltype, row.n_cells) }, 
        ch_ensembl_mappings3 
    )

    SCFLOW_IPA ( 
        SCFLOW_DGE.out.de_table 
    )

    SCFLOW_DIRICHLET ( 
        SCFLOW_FINALIZE.out.final_sce 
    )

    SCFLOW_PLOTREDDIMGENES ( 
        SCFLOW_CLUSTER.out.clustered_sce, 
        ch_reddim_genes_yml
    )
}

  /*
  publish:
    SCFLOW_CHECK_INPUTS.out.checked_input to: "$params.outdir/", mode: 'copy', overwrite: 'true'
    // Quality-control
    SCFLOW_QC.out.qc_report to: "$params.outdir/Reports/", mode: 'copy', overwrite: 'true'
    SCFLOW_QC.out.qc_plot_data to: "$params.outdir/Tables/Quality_Control/", mode: 'copy', overwrite: 'true'
    SCFLOW_QC.out.qc_plots to: "$params.outdir/Plots/Quality_Control/", mode: 'copy', overwrite: 'true'
    SCFLOW_QC.out.qc_sce to: "$params.outdir/SCE/Individual/", mode: 'copy', overwrite: 'true'
    SCFLOW_MERGE_QC_SUMMARIES.out.qc_summary to: "$params.outdir/Tables/Merged/", mode: 'copy', overwrite: 'true'
    // Merged SCE
    SCFLOW_MERGE.out.merged_report to: "$params.outdir/Reports/", mode: 'copy', overwrite: 'true'
    SCFLOW_MERGE.out.merge_plots to: "$params.outdir/Plots/Merged/", mode: 'copy', overwrite: 'true'
    SCFLOW_MERGE.out.merge_summary_plots to: "$params.outdir/Plots/Merged/", mode: 'copy', overwrite: 'true'
    // cluster
    SCFLOW_CLUSTER.out.integration_report to: "$params.outdir/Reports/", mode: 'copy', overwrite: 'true'
    // ct
    SCFLOW_MAP_CELLTYPES.out.celltype_mappings to: "$params.outdir/Tables/Celltype_Mappings", mode: 'copy', overwrite: 'true'
    // final
    SCFLOW_FINALIZE.out.final_sce to: "$params.outdir/SCE/", mode: 'copy', overwrite: 'true'
    SCFLOW_FINALIZE.out.celltypes to: "$params.outdir/Tables/Celltype_Mappings", mode: 'copy', overwrite: 'true'
    SCFLOW_FINALIZE.out.celltype_metrics_report to: "$params.outdir/Reports/", mode: 'copy', overwrite: 'true'
    // DE
    SCFLOW_DGE.out.de_table to: "$params.outdir/Tables/DGE", mode: 'copy', optional: 'true', overwrite: 'true'
    SCFLOW_DGE.out.de_report to: "$params.outdir/Reports/", mode: 'copy', optional: 'true', overwrite: 'true'
    SCFLOW_DGE.out.de_plot to: "$params.outdir/Plots/DGE/", mode: 'copy', optional: 'true', overwrite: 'true'
    SCFLOW_DGE.out.de_plot_data to: "$params.outdir/Tables/DGE", mode: 'copy', optional: 'true', overwrite: 'true'
    // IPA
    SCFLOW_IPA.out.ipa_results to: "$params.outdir/Tables/", mode: 'copy', optional: true, overwrite: 'true'
    SCFLOW_IPA.out.ipa_report to: "$params.outdir/Reports/", mode: 'copy', optional: true, overwrite: 'true'
    // Dirichlet
    SCFLOW_DIRICHLET.out.dirichlet_report to: "$params.outdir/Reports/", mode: 'copy', overwrite: 'true'
    // plots
    SCFLOW_PLOT_REDDIM_GENES.out.reddim_gene_plots to: "$params.outdir/Plots/", mode: 'copy', overwrite: 'true'
}
/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/scflow] Successful: $workflow.runName"
    if (!workflow.success) {
        subject = "[nf-core/scflow] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
        log.info "-${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}-"
        log.info "-${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}-"
        log.info "-${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}-"
    }

    if (workflow.success) {
        log.info "-${c_purple}[nf-core/scflow]${c_green} Pipeline completed successfully${c_reset}-"
    } else {
        checkHostname()
        log.info "-${c_purple}[nf-core/scflow]${c_red} Pipeline completed with errors${c_reset}-"
    }

}

workflow.onError {
    // Print unexpected parameters - easiest is to just rerun validation
    NfcoreSchema.validateParameters(params, json_schema, log)
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = 'hostname'.execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "${c_red}====================================================${c_reset}\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "${c_red}====================================================${c_reset}\n"
                }
            }
        }
    }
}
