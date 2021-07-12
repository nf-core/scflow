/*
 * Merge quality-control passed SCEs
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_MERGE {
    tag "MERGED"
    label 'process_medium'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path qc_passed_sces
    path ensembl_mappings

    output:
    path 'merged_sce/'              , emit: merged_sce          , type: 'dir'
    path 'merge_plots'              , emit: merge_plots         , type: 'dir'
    path 'merge_summary_plots'      , emit: merge_summary_plots , type: 'dir'
    path 'merged_report'            , emit: merged_report       , type: 'dir'

    script:
    def software = getSoftwareName(task.process)

    """

    scflow_merge.r \
    $options.args \
    --sce_paths ${qc_passed_sces.join(',')} \
    --ensembl_mappings ${ensembl_mappings} \

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
