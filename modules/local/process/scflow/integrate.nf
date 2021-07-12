/*
 * Integrate data for batch-effect correction
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_INTEGRATE {
    tag "MERGED"
    label 'process_medium'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path sce

    output:
    path 'integrated_sce/', emit: integrated_sce

    script:
    def software = getSoftwareName(task.process)


    """
    export MC_CORES=${task.cpus}

    scflow_integrate.r \
    $options.args \
    --sce_path ${sce}

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
