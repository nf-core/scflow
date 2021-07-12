/*
 * Merge individual quality-control tsv summaries into combined tsv file
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_MERGEQCTABLES {
    tag 'MERGEQCTABLES'
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path qcs_tsv
    
    output:
    path '*.tsv', emit: qc_summary

    script:
    def software = getSoftwareName(task.process)


    """
    merge_tables.r \
    $options.args \
    --filepaths ${qcs_tsv.join(',')}

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
