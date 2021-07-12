/*
 * Generate final SCE with optionally revised cell-types
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_FINALIZE {
    tag "MERGED"
    label 'process_high'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path sce
    path celltype_mappings

    output:
    path 'final_sce'                , emit: final_sce, type: 'dir'
    path 'celltypes.tsv'            , emit: celltypes
    path 'celltype_metrics_report'  , emit: celltype_metrics_report, type: 'dir'

    script:
    def software = getSoftwareName(task.process)


    """
    export MC_CORES=${task.cpus}

    scflow_finalize_sce.r \
    $options.args \
    --sce_path ${sce} \
    --celltype_mappings ${celltype_mappings}

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
