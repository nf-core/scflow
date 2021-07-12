/*
 * Generate 2D reduced dimension plots of gene expression
 */

// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

process SCFLOW_DGE {
    tag "${celltype} (${n_cells_str} cells) | ${de_method}"
    label 'process_medium'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:"${celltype}_${de_method}") }

//    container 'combiz/scflow-docker:0.6.1'
    
    input:
    path sce
    each de_method
    each ct_tuple
    path ensembl_mappings

    output:
    path 'de_table/*.tsv' , emit: de_table      , optional: true
    path 'de_report'      , emit: de_report     , type: 'dir', optional: true
    path 'de_plot'        , emit: de_plot       , type: 'dir', optional: true
    path 'de_plot_data'   , emit: de_plot_data  , type: 'dir', optional: true

    script:
    celltype     = ct_tuple[0]
    n_cells      = ct_tuple[1].toInteger()
    n_cells_str  = (Math.round(n_cells * 100) / 100000).round(1).toString() + 'k'
    def software = getSoftwareName(task.process)


     """
    echo "celltype: ${celltype} n_cells: ${n_cells_str}"
    export MC_CORES=${task.cpus}
    export MKL_NUM_THREADS=1
    export NUMEXPR_NUM_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export VECLIB_MAXIMUM_THREADS=1
    scflow_dge.r \
    $options.args \
    --sce ${sce} \
    --celltype ${celltype} \
    --de_method ${de_method} \
    --ensembl_mappings ${ensembl_mappings}

    scflow_version=\$(Rscript -e 'cat(as.character(utils::packageVersion("scFlow")))'); echo "scFlow \${scflow_version}" > "scFlow_\${scflow_version}.version.txt"
    """
}
