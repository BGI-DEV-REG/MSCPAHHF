rm(list=ls())
gc()

library(Seurat)
library(ggplot2)
library(dplyr)
library(stringr)
library(grid)
library(tibble)
library(stringr)
library(parallel)
library(RColorBrewer)
library(future)
library(patchwork)
setwd('../data/figure2/monocle3/HFSC')

options(future.globals.maxSize = 200 * 1024^3)

colorlist = read.delim('../data/RCTD.color_LastlEdition240612.txt')
colors = colorlist$Color
names(colors) = colorlist$order

# subset HFSC-lineage related celltypes and re-integrated
obj=readRDS('../data/figure1/scRNA-seq/HF_RNA_postQC_rpca.rds')
Idents(obj) = obj$celltype
obj = subset(obj, idents = c("ORS_basal", "Active_HFSC","ORS_Suprabasal", "TAC_3", "Quiescent_HFSC", "Medulla_Cortex_Cuticle", "HF_IRS", "TAC_2", "IRS_cuticle"))
DefaultAssay(obj) = 'RNA'

HF.list = SplitObject(obj, split.by = 'batch1')
HF.list = lapply(HF.list, function(x){
    DefaultAssay(x) = 'RNA'
    x = x %>% NormalizeData(., verbose = F) %>% FindVariableFeatures(., verbose = F) %>% ScaleData(., verbose = F) %>% RunPCA(., npcs = 30, verbose = F)
    x <- ScaleData(x, features = rownames(obj), verbose = FALSE)
    x <- RunPCA(x, npcs = 30, verbose = FALSE)
})

features <- SelectIntegrationFeatures(object.list = HF.list)
anchors <- FindIntegrationAnchors(object.list = HF.list, anchor.features = features, reduction = "cca", verbose = F)
obj <- IntegrateData(anchorset = anchors)

DefaultAssay(obj) <- "integrated"
obj <- ScaleData(obj, features = rownames(obj), verbose = FALSE)
obj <- RunPCA(obj, npcs = 30, verbose = FALSE, reduction.name = 'inter_pca')
seed = 4
dist = 0.3
obj <- RunUMAP(obj, reduction = "inter_pca", dims = 1:30, seed.use = seed, verbose = F, min.dist = dist)
s.genes <- cc.genes$s.genes
g2m.genes <- cc.genes$g2m.genes
obj <- CellCycleScoring(obj, s.features = s.genes, g2m.features = g2m.genes, set.ident = FALSE)

saveRDS(obj, '../data/figure2/monocle3/HFSC/HF_RNA_HFSC_lineage_cca.rds')


# monocle analysis

library(monocle3)

DefaultAssay(obj) = 'RNA'

data <- GetAssayData(obj, assay = 'RNA', slot = 'counts')
cell_metadata <- obj@meta.data
gene_annotation <- data.frame(gene_short_name = rownames(data))
rownames(gene_annotation) <- rownames(data)
cds <- new_cell_data_set(data,
                         cell_metadata = cell_metadata,
                         gene_metadata = gene_annotation)
              
## pre-process
cds <- preprocess_cds(cds, num_dim = 50)
# plot_pc_variance_explained(cds)

cds <- reduce_dimension(cds,preprocess_method = "PCA")
# plot_cells(cds)

cds <- cluster_cells(cds, reduction_method = "UMAP")

fData(cds)$gene_short_name <- rownames(fData(cds))

recreate.partitions <- c(rep(1, length(cds@colData@rownames)))
names(recreate.partitions) <- cds@colData@rownames
recreate.partitions <- as.factor(recreate.partitions)
head(recreate.partitions)

cds@clusters@listData[["UMAP"]][["partitions"]] <- recreate.partitions

list.cluster <-obj@active.ident
cds@clusters@listData[["UMAP"]][["clusters"]] <- list.cluster

cds@int_colData@listData[["reducedDims"]]@listData[["UMAP"]] <- obj@reductions$umap@cell.embeddings
cds <- learn_graph(cds, use_partition = TRUE)

## set root cell
get_earliest_principal_node <- function(cds, time_bin=c('DEGC')){
  # 
  cell_ids <- which(colData(cds)[, "celltype"] == time_bin)
  # 
  closest_vertex <- cds@principal_graph_aux[["UMAP"]]$pr_graph_cell_proj_closest_vertex
  closest_vertex <- as.matrix(closest_vertex[colnames(cds), ])
  # 
  root_pr_nodes <- igraph::V(principal_graph(cds)[["UMAP"]])$name[as.numeric(names(which.max(table(closest_vertex[cell_ids,]))))]
  root_pr_nodes
}

nodes_vec <- get_earliest_principal_node(cds,"Quiescent_HFSC")
cds = order_cells(cds, root_pr_nodes=nodes_vec,reduction_method = "UMAP")

cds$monocle3_pseudotime <- pseudotime(cds)
data.pseudo <- as.data.frame(colData(cds))

options(repr.plot.width = 10, repr.plot.height = 10)
p1 = plot_cells(cds, 
                reduction_method="UMAP", 
                color_cells_by="celltype", 
                trajectory_graph_color = "white", 
                show_trajectory_graph = T, 
                label_leaves = F, 
                label_roots = F,
                cell_size = 1,
                trajectory_graph_segment_size = 1.5,
                label_branch_points = F, 
                label_cell_groups = F) + 
    scale_color_manual(values = colors)+
    theme_void() + 
    theme(legend.position = "none",
          legend.text = element_text(color = "white"),
          legend.title = element_text(color = "white"),
          panel.border = element_blank(),
          panel.grid = element_blank(),
          axis.text = element_blank(),
          axis.title = element_blank(),
          axis.line = element_blank())
p1
ggsave(plot = p1, file = paste0("cds_pseudotime_Celltype.pdf"), width = 10, height = 10)
ggsave(plot = p1, file = paste0("cds_pseudotime_Celltype.png"), width = 10, height = 10)

p2 = plot_cells(cds = cds,
                color_cells_by = "pseudotime",
                trajectory_graph_color = "white", 
                show_trajectory_graph = T, 
                label_leaves = F, 
                label_roots = F,
                cell_size = 1,
                trajectory_graph_segment_size = 1.5,
                label_branch_points = F, 
                label_cell_groups = F) + viridis::scale_color_viridis(option = "D") + 
    theme_void() + 
    theme(legend.position = "right",
          legend.text = element_text(color = "white"),
          legend.title = element_text(color = "white"),
          panel.border = element_blank(),
          panel.grid = element_blank(),
          axis.text = element_blank(),
          axis.title = element_blank(),
          axis.line = element_blank())
p2
ggsave(plot = p2, file = paste0("cds_pseudotime.pdf"), width = 10, height = 10)
ggsave(plot = p2, file = paste0("cds_pseudotime.png"), width = 10, height = 10)


## trajectory genes enrichment
Track_genes <- graph_test(cds, neighbor_graph="principal_graph", cores=8)
Track_genes <- Track_genes[,c(2,3,4,5,6)] %>% filter(q_value < 1e-3)
write.csv(Track_genes, "Trajectory_genes.csv", row.names = F)

### heatmap
library(ComplexHeatmap)
library(RColorBrewer)
library(circlize)

Track_genes1 = Track_genes %>% filter(p_value < 0.05) %>% top_n(3000, wt = morans_I)
dim(Track_genes1)

pdata = pData(cds)
obj$pseudotime = pdata[Cells(obj), 'monocle3_pseudotime']

rownames(abbreviation) = colorlist$order
obj$celltype_2 = colors[obj$celltype, 'abbreviation']
unique(obj$celltype_2) %>% sort

lineage = c('qHFSC','aHFSC','ORSB','ORSS','TAC1','IRS','TAC2','IRSC','MCC')
obj$celltype_2 = factor(obj$celltype_2, level = lineage)
levels(obj$celltype_2)

meta = obj@meta.data
meta = meta %>% tibble::rownames_to_column(.,'Cell') %>% 
    group_by(celltype_2) %>% 
    arrange(celltype_2,pseudotime) %>% 
    mutate(bin = ntile(pseudotime, 20)) %>% 
    mutate(rank = paste0(as.character(celltype_2),'.',bin)) %>%
    tibble::column_to_rownames(.,'Cell')
# head(meta,3)

obj$bin = meta[Cells(obj), 'bin']
obj$rank = meta[Cells(obj), 'rank']
# head(obj,3)

exp <- t(as.matrix(GetAssayData(obj, assay = 'RNA', slot = 'data')))
HFSC_exp = aggregate(exp, FUN = mean, by = list(obj$rank))
HFSC_exp %>% 
  column_to_rownames("Group.1") -> df 

df_t <- t(df)
df_t_gene <- df_t[rownames(df_t) %in% Track_genes1$gene_short_name,]
gene_sd<-apply(df_t_gene,1,sd)
df_sd <- cbind(df_t_gene,gene_sd)
df_sd[1:3,]
dim(df_sd)
write.csv(df_sd,"KC_sd.csv")

df_sd = read.csv('KC_sd.csv',row.names=1)

df_sd = df_sd[, -ncol(df_sd)]
df_sd_t <- t(df_sd)

mat_cha <- t(scale(df_sd_t))

mat_cha[mat_cha >= 3] = 3
mat_cha[mat_cha <= -3] = -3
mat_cha_smooth <- mat_cha[, unique(meta$rank)]
mat_cha_smooth <- t(apply(mat_cha_smooth,1,function(x){smooth.spline(x,df=3)$y}))
mat_cha_smooth[mat_cha_smooth >= 3] = 3
mat_cha_smooth[mat_cha_smooth <= -3] = -3

colnames(mat_cha_smooth) = unique(meta$rank)

set.seed(2024)

options(repr.plot.width = 5, repr.plot.height = 5)
k_means <- 18
p_clust=pheatmap::pheatmap(mat_cha,
                     cutree_rows=k_means, breaks = seq(-3,3, by = 0.1),
                     cluster_cols = F,show_rownames = FALSE,
                     show_colnames = FALSE)
split_matrix=data.frame(cutree(p_clust$tree_row,k=k_means))

data.meta = meta %>% select(celltype_2, rank) %>% distinct
data.meta$color = colors[match(data.meta$celltype_2, colors$abbreviation), 'Color']
head(data.meta,3)

column_ha = HeatmapAnnotation(
  pattern = data.meta$rank,
  col = list(pattern = setNames(data.meta$color, data.meta$rank))
)

options(repr.plot.width = 15, repr.plot.height = 18)
clust_hm2 <- Heatmap(mat_cha_smooth,name='Exp',
                     circlize::colorRamp2(c(-3,0,0.2,1,2), brewer.pal(11, "RdBu")[c(10,6,4,2,1)]),
                     left_annotation = rowAnnotation(foo = anno_block(gp = gpar(fill = 2:21),
                                                                      labels_gp = gpar(col = "white", fontsize = 8))),
                     row_split = split_matrix,
                     top_annotation = column_ha,
                     cluster_columns = FALSE,
                     #right_annotation = ha,
                     show_row_names = FALSE,
                     show_column_names = FALSE)
clust_hm2

split_matrix1 = split_matrix %>% 
    mutate(order = p_clust$tree_row$order) %>%
    # rownames_to_column(.,'gene') %>%
    rename('module' = 'cutree.p_clust.tree_row..k...k_means.') %>%
    arrange(module)
unique(split_matrix1$module)
head(split_matrix1)

module.levels = c(
    6,1,13,2,8,12,15,9,3,4,5,14,7,10,11
)%>% rev
genelist = split_matrix1
genelist$module = factor(genelist$module, level = module.levels)
genelist = genelist %>% rownames_to_column(.,'gene') %>% group_by(module) %>% arrange(module,order)
head(genelist,3)

tf = read.delim('../data/database/allTFs_hg38.txt',header=F) %>% dplyr::rename('TF' = 'V1')
head(tf,3)

scenic = read.csv('/data/work/01.HF_RNA/KC_lineage/SCENIC/ctx.csv')
colnames(scenic) = c(scenic[2,c(1:2)], scenic[1,-c(1:2)])
scenic = scenic[-c(1:2),]
head(scenic,3)

gene = c('ANGPTL7','FGF18','FZD7','CXCL14','LHX2','KRT15',
         'NDUFB7','NDUFC2','NDUFA6','HK1','LDHA','SMC4','YWHAG','PDK1','PDK4','PDHA1','MAP1LC3B','SQSTM1','ATG3','HIF1A','SOD2','ATF4',
         'LGR5','CD34','FOXC1','NFATC1','S100A4')
gene = union(gene, scenic$TF) %>% sort
gene

options(repr.plot.width = 10, repr.plot.height = 12)
mat_cha_smooth1 = mat_cha_smooth[genelist$gene, ]
clust_hm2 <- Heatmap(mat_cha_smooth1, name='Exp',
                     # row_order = rownames(genelist),
                     circlize::colorRamp2(c(-3,0,0.2,0.6,1.5), brewer.pal(11, "RdBu")[c(10,6,4,2,1)]),
                     # left_annotation = rowAnnotation(foo = anno_block(gp = gpar(fill = 2:19),
                     #                                                  labels_gp = gpar(col = "white", fontsize = 8))),
                     # colorRamp2(c(-3,0,3), c('#3E9BFEFF','white','#F05B12FF')),
                     # left_annotation = row_ha,
                     # cluster_rows = FALSE,
                     cluster_row_slices = TRUE,
                     clustering_distance_rows = "euclidean",
                     clustering_method_rows = "complete",
                     row_split = genelist$module,
                     top_annotation = column_ha,
                     cluster_columns = FALSE,
                     # cluster_rows = FALSE,
                     #right_annotation = ha,
                     show_row_names = FALSE,
                     show_column_names = FALSE,
                     use_raster = T)+
  rowAnnotation(link = anno_mark(at = which(rownames(mat_cha_smooth1) %in% gene), 
                                   labels = rownames(mat_cha_smooth1)[which(rownames(mat_cha_smooth1) %in% gene)], labels_gp = gpar(fontsize = 6)))
clust_hm2

pdf('HF_KC_lineage_heatmap.pdf', width = 10, height = 12)
clust_hm2
dev.off()

