# Copyright (c) [2021] [Ricardo O. Ramirez Flores]
# roramirezf@uni-heidelberg.de

#' Test a simplified version of the spatial analysis of interacting cells of interest

library(tidyverse)
library(Seurat)
library(mistyR)
library(ggpubr)
library(viridis)
library(cowplot)
source("./analysis/utils/misty_pipeline.R")
source("./analysis/utils/spatial_plots_utils.R")

# Get patient annotation
annotation_names <- tibble(patient_group = c("group_1", "group_2", "group_3"),
                           patient_group_name = c("myogenic-enriched", "ischemic-enriched", "fibrotic-enriched"))

sample_dict <- read_csv("./markers/visium_patient_anns_revisions.csv") %>%
  left_join(annotation_names) %>%
  dplyr::select(-patient_group) %>%
  dplyr::rename("patient_group" = patient_group_name) %>%
  dplyr::mutate(patient_group = factor(patient_group, 
                                       levels = c("myogenic-enriched", "ischemic-enriched", "fibrotic-enriched")))

# Explained variance filter
r2_filter <- 10
misty_out_folder <- "./results/state_structure/Fib_Myeloid/"
misty_outs <- list.files(misty_out_folder, full.names = T)
misty_outs <- misty_outs[grepl("mstate", misty_outs)]

misty_res <- collect_results(misty_outs)

model_performance <- misty_res$improvements %>% dplyr::filter(grepl("intra.R2", measure) | 
                                                                grepl("multi.R2", measure) |
                                                                grepl("multi.RMSE", measure))  %>%
  mutate(sample = strsplit(sample, 'mstate_') %>%
           map_chr(., ~.x[[2]]))

R2_data <- model_performance %>% 
  dplyr::filter(measure == "multi.R2") %>% 
  group_by(target) %>%
  left_join(sample_dict, by = c("sample" = "sample_id"))

RMSE_data <- model_performance %>% 
  dplyr::filter(measure == "multi.RMSE") %>% 
  group_by(target) %>%
  left_join(sample_dict, by = c("sample" = "sample_id"))


# First show that there are differences in performance of different markers
mrkr_order <- R2_data %>%
  group_by(target) %>%
  summarize(med_imp = median(value)) %>%
  arrange(-med_imp) %>%
  pull(target)

R2_data_plt_mrkrs <- R2_data %>%
  ggplot(aes(x = factor(target,
                        levels = mrkr_order), y = value)) +
  geom_boxplot() +
  geom_point() +
  theme_classic() +
  theme(axis.text = element_text(size = 10),
        axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
        legend.position = "none") +
  ylab("Explained variance") +
  xlab("") +
  stat_compare_means(label.y = 90)

write_csv(R2_data, paste0(misty_out_folder,"mrkr_R2.csv"))

pdf(paste0(misty_out_folder,"mrkr_R2.pdf"), height = 4, width = 3)
plot(R2_data_plt_mrkrs)
dev.off()

RMSE_data_plt_mrkrs <- RMSE_data %>%
  ggplot(aes(x = factor(target,
                        levels = mrkr_order), y = value)) +
  geom_boxplot() +
  geom_point() +
  theme_classic() +
  theme(axis.text = element_text(size = 10),
        axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
        legend.position = "none") +
  ylab("RMSE") +
  xlab("") +
  stat_compare_means(label.y = 4)

pdf(paste0(misty_out_folder,"mrkr_RMSE.pdf"), height = 4, width = 3)
plot(RMSE_data_plt_mrkrs)
dev.off()

# Then show the contributions

contributions <- misty_res$contributions %>%
  dplyr::filter(!stringr::str_starts(.data$view, "p\\.") &
                  .data$view != "intercept") %>%
  mutate(sample = strsplit(sample, 'mstate_') %>%
           map_chr(., ~.x[[2]])) %>%
  group_by(sample) %>%
  nest() %>%
  dplyr::mutate(data = map(data, function(dat) {
    dat %>%
      dplyr::group_by(.data$target, .data$view) %>%
      dplyr::summarise(mean = mean(.data$value), .groups = "drop_last") %>%
      dplyr::mutate(fraction = abs(.data$mean) / sum(abs(.data$mean))) %>%
      dplyr::ungroup()
  })) %>%
  unnest() %>%
  ungroup()

cont_plt_mrkrs <- ggplot(contributions, aes(x = target, y = fraction, fill = view)) +
  geom_boxplot() +
  theme_classic() +
  theme(axis.text = element_text(size = 10),
        axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
  ylab("View contribution") +
  xlab("")

write_csv(contributions, file = paste0(misty_out_folder,"mrkr_contributions.csv"))

pdf(paste0(misty_out_folder,"mrkr_contributions.pdf"), height = 4, width = 5)
plot(cont_plt_mrkrs)
dev.off()

# Then get best in class

best_performers <- R2_data %>% 
  dplyr::filter(value >= r2_filter) %>%
  pull(sample) 


importances_filtered <- misty_res$importances %>%
  mutate(sample = strsplit(sample, 'mstate_') %>%
           map_chr(., ~.x[[2]])) %>%
  left_join(sample_dict, by = c("sample" = "sample_id")) %>%
  dplyr::filter(sample %in% best_performers) 

# Plot importances for all the slides, regardless the patient group

summarized_importances <- importances_filtered %>%
  na.omit() %>%
  group_by(view, Target, Predictor) %>%
  summarise(mean_imp = mean(Importance),
            median_imp = median(Importance)) %>%
  ungroup()


# Calculate difference from 0

imp_p <- importances_filtered %>%
  na.omit() %>%
  select(view, Predictor, Target, Importance) %>%
  group_by(view, Predictor, Target) %>%
  nest() %>%
  mutate(wilcox_res = map(data, function(dat) {
    
    wilcox.test(dat$Importance, y = NULL, mu = 0, alternative = "greater") %>%
      broom::tidy()
    
    
  })) %>%
  dplyr::select(-data) %>%
  unnest() %>%
  ungroup() %>%
  dplyr::mutate(p_corr = p.adjust(p.value)) %>%
  group_by(view) %>%
  dplyr::mutate(sign_symbol = ifelse(p_corr <= 0.15, "*", "")) %>%
  dplyr::select(-c("statistic", "method", "alternative"))

summarized_importances <- summarized_importances %>%
  left_join(imp_p, by = c("view", "Predictor", "Target"))

write_csv(summarized_importances, file = paste0(misty_out_folder,"summarized_importances.csv"))

# Plot heatmaps

summarized_importances_plts <- summarized_importances %>%
  group_by(view) %>%
  nest() %>%
  mutate(gplots = map2(view, data, function(v, dat) {
    
    imp_plot <- dat %>%
      ggplot(., aes(x = Target, y = Predictor, fill = median_imp, label = sign_symbol)) +
      geom_tile() +
      geom_text() +
      theme_classic() +
      scale_fill_gradient2(high = "#8DA0CB", 
                           midpoint = 0,
                           low = "white",
                           na.value = "grey") +
      ggplot2::coord_equal() +
      theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
      ggtitle(v)
    
  }))


walk2(summarized_importances_plts$view, summarized_importances_plts$gplots, function(v, gplot) {
  
  pdf_out <- paste0(misty_out_folder,"/median_importances", "_", v, ".pdf")
  
  pdf(pdf_out, height = 4, width = 5)
  
  plot(gplot)
  
  dev.off()
  
})



# Now we need to ask about each single marker
# Do we see a difference in R2, contributions?

my_comparisons <- list( c("myogenic-enriched", "ischemic-enriched"), 
                        c("myogenic-enriched", "fibrotic-enriched"), 
                        c("ischemic-enriched", "fibrotic-enriched") )

R2_group_comparisons <- R2_data %>%
  group_by(target) %>%
  nest() %>%
  mutate(gplot = map2(target, data, function(trgt, dat) {
    
    ggplot(dat, aes(x = patient_group, y = value, color = patient_group)) +
      geom_boxplot() +
      geom_point() +
      theme_classic() +
      theme(axis.text = element_text(size = 12),
            axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
      ggtitle(trgt) +
      stat_compare_means(comparisons = my_comparisons, label="p.adj") +
      ylab("Explained Variance") +
      xlab("")
    
  }))


pdf(file = paste0(misty_out_folder,"/R2_group_comparisons.pdf"), height = 5, width = 4)

walk(R2_group_comparisons$gplot, plot)

dev.off()

# Now contributionss
# Space may matter more in one group vs other

contributions_filtered <- contributions %>%
  left_join(sample_dict, by = c("sample" = "sample_id")) %>%
  dplyr::filter(sample %in% best_performers) %>%
  group_by(target, view) %>%
  nest() 

contribution_gcomp_plts <- pmap(contributions_filtered, function(target, view, data) {
  
  ggplot(data, aes(x = patient_group, y = fraction, 
                   color = patient_group)) +
    geom_boxplot() +
    geom_point() +
    theme_classic() +
    theme(axis.text = element_text(size = 12),
          axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
    ggtitle(target) +
    stat_compare_means(comparisons = my_comparisons, label="p.adj") +
    ylab("View contribution") +
    xlab(view)
  
  
})

pdf(file = paste0(misty_out_folder,"/contribution_group_comparisons.pdf"), height = 5, width = 4)

walk(contribution_gcomp_plts, plot)

dev.off()

# Make boxplots of importances

views <- importances_filtered$view %>% unique()

walk(views, function(v) {
  
  pdf_out <- paste0(misty_out_folder,"/importance_distributions_", v, ".pdf")
  
  pdf(file = pdf_out, height = 5, width = 6)
  
  plt <- importances_filtered %>%
    na.omit() %>%
    dplyr::filter(view == v) %>%
    ggplot(aes(x = Predictor, y = Importance)) +
    geom_boxplot() +
    geom_point(aes(color = patient_group)) +
    facet_wrap(.~Target) +
    theme_classic() +
    theme(axis.text = element_text(size = 12),
          axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
          panel.border = element_rect(colour = "black", fill=NA, size=1))
  
  plot(plt)
  
  dev.off()
  
}
)

# Plot best examples:

samples <- importances_filtered %>%
  dplyr::filter(Target == "Fib.Myofib",
                Predictor == "Myeloid.Monocyte.SPP1") %>%
  arrange(-Importance) %>%
  dplyr::slice(1:15) %>%
  pull(sample) %>%
  unique()

walk(samples, function(s) {
  
  print(s)
  
  slide_id <- s
  slide_file <- paste0(s, ".rds")
  state_origin <- "cell_states"
  print(slide_file)
  slide_files_folder <- "./processed_visium/objects/"
  
  # Read spatial transcriptomics data and transform states to be useful for modeling
  slide <- readRDS(paste0(slide_files_folder, slide_file)) %>%
    positive_states(., assay = state_origin) %>%
    filter_states(slide = .,
                  by_prop = F,
                  prop_thrsh = 0.1)
  
  DefaultAssay(slide) <- "c2l"
  
  ct_plot <- SpatialFeaturePlot(slide, 
                                   features = "Fib",
                                   min.cutoff = "q1",
                                   max.cutoff = "q99", 
                                   stroke = 0,
                                   pt.size.factor = 1.5) +
    scale_fill_viridis(option = "B")
  
  DefaultAssay(slide) <- "cell_states_pos"
  
  state_plot <- SpatialFeaturePlot(slide, 
                                   features = "Fib-Myofib",
                                   min.cutoff = "q1",
                                   max.cutoff = "q99", 
                                   stroke = 0,
                                   pt.size.factor = 1.5) +
    scale_fill_viridis(option = "D")
  
  myeloid_state_plot <- SpatialFeaturePlot(slide, 
                                   features = "Myeloid-Monocyte-SPP1",
                                   min.cutoff = "q1",
                                   max.cutoff = "q99", 
                                   stroke = 0,
                                   pt.size.factor = 1.5) +
    scale_fill_viridis(option = "D")
  
  
  pdf(paste0("./results/state_structure/Fib_Myeloid/myof_spp1_examples/", slide_id,
             "_myof_allslide.pdf"), height = 6, width = 9)
  
  plot(cowplot::plot_grid(ct_plot, state_plot, myeloid_state_plot,nrow = 1))
  
  dev.off()
  
})

# Plot CCL18 and other things


samples <- importances_filtered %>%
  dplyr::filter(Predictor == "Myeloid.Monocyte.CCL18") %>%
  arrange(-Importance) %>%
  dplyr::slice(1:10) %>%
  dplyr::select(sample, Target)
 
walk2(samples$sample, samples$Target, function(s, target) {
  
  print(s)
  
  slide_id <- s
  slide_file <- paste0(s, ".rds")
  state_origin <- "cell_states"
  print(slide_file)
  slide_files_folder <- "./processed_visium/objects/"
  
  # Read spatial transcriptomics data and transform states to be useful for modeling
  slide <- readRDS(paste0(slide_files_folder, slide_file)) %>%
    positive_states(., assay = state_origin) %>%
    filter_states(slide = .,
                  by_prop = F,
                  prop_thrsh = 0.1)
  
  DefaultAssay(slide) <- "cell_states_pos"
  
  
  target <- gsub("[.]","-", target)
  
  state_plot <- SpatialFeaturePlot(slide, 
                                   features = target,
                                   max.cutoff = "q99", 
                                   min.cutoff = "q1",
                                   stroke = 0,
                                   pt.size.factor = 1.5) +
    scale_fill_viridis(option = "D")
  
  myeloid_state_plot <- SpatialFeaturePlot(slide, 
                                           features = "Myeloid-Monocyte-CCL18",
                                           max.cutoff = "q99", 
                                           min.cutoff = "q1",
                                           stroke = 0,
                                           pt.size.factor = 1.5) +
    scale_fill_viridis(option = "D")
  
  
  pdf(paste0("./results/state_structure/Fib_Myeloid/fib_ccl18_examples/", slide_id,
             "_myof_allslide.pdf"), height = 6, width = 6)
  
  plot(cowplot::plot_grid(state_plot, myeloid_state_plot))
  
  dev.off()
  
})
