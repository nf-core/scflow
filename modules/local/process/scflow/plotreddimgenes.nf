/*
 * Generate 2D reduced dimension plots of gene expression
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_PLOTREDDIMGENES {
    tag "MERGED"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path sce
    path reddim_genes_yml

    output:
    path 'reddim_gene_plots/', emit: reddim_gene_plots

    script:
    def software = getSoftwareName(task.process)


    """
    export MC_CORES=${task.cpus}

    scflow_plot_reddim_genes.r \
    $options.args \
    --sce ${sce} \
    --reddim_genes_yml ${reddim_genes_yml}    

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
