/*
 * Annotate cluster celltypes
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_MAPCELLTYPES {
    tag "MERGED"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path sce
    path ctd_path

    output:
    path 'celltype_mapped_sce/' , emit: celltype_mapped_sce, type: 'dir'
    path 'celltype_mappings.tsv', emit: celltype_mappings

    script:
    def software = getSoftwareName(task.process)


    """
    export MC_CORES=${task.cpus}

    mkdir ctd_folder && unzip ${ctd_path} -d ./ctd_folder
    

    scflow_map_celltypes.r \
    $options.args \
    --sce_path ${sce} \
    --ctd_folder ctd_folder

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
