/*
 * Check input manifest and samplesheet inputs are valid
 */
 

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_CHECKINPUTS {
    tag "SCFLOW_CHECKINPUTS"
    label 'process_tiny'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

    //container "combiz/scflow-docker:0.6.1"
    
    input:
    path input
    path samplesheet
    
    output:
    path 'checked_input.txt', emit: checked_input

    script:
    def software = getSoftwareName(task.process)

    """
    check_inputs.r \\
        --samplesheet $samplesheet \
        --manifest $input
        
    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
