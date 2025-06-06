# Copyright (c) [2021] [Ricardo O. Ramirez Flores]
# roramirezf@uni-heidelberg.de

#' Copying cell2location models to simpler paths
library(tidyverse)

# Identifying location models
root_path <- "./results/deconvolution_models/"
c2l_files <- list.files(root_path)
c2l_files <- c2l_files[grepl("LocationModel", c2l_files)] %>%
  gsub("[.]/", "", .) %>%
  paste0(.,"/")

samples <- gsub("/","", map_chr(strsplit(c2l_files,"genes_"), last))
plots_file <- "plots"
density <- "W_cell_density.csv"  
density_q <- "W_cell_density_q05.csv"


# Copy the plots folder of each model to location_models/plots
walk2(c2l_files, samples, function(c2l_f, s) {
  
  print(c2l_f)
  
  # First copy as it is
  system(paste0("cp -R ", 
                root_path, 
                c2l_f, 
                plots_file,
                paste0(" ", root_path, "location_models/plots/")
                ))
  
  # Then rename
  
  system(paste0("mv",
                paste0(" ", root_path, "location_models/plots/"),
                plots_file,
                paste0(" ", root_path, "location_models/plots/"),
                plots_file,
                "_",
                s))
  
})

# Copy the density file of each model to location_models/density_tables

walk2(c2l_files, samples, function(c2l_f, s) {
  
  print(c2l_f)
  
  # First copy
  
  system(paste0("cp ", 
                root_path, 
                c2l_f, 
                density,
                paste0(" ", root_path, "location_models/density_tables/")))
  
  # Then move
  
  system(paste0("mv",
                paste0(" ", root_path, "location_models/density_tables/"),
                density,
                paste0(" ", root_path, "location_models/density_tables/"),
                s,
                "_",
                density))
  
})

# Copy the density file of each model to location_models/density_tables

walk2(c2l_files, samples, function(c2l_f, s) {
  
  print(c2l_f)
  
  system(paste0("cp ", 
                root_path, 
                c2l_f, 
                density_q,
                paste0(" ", root_path, "location_models/density_tables/")))
  
  system(paste0("mv",
                paste0(" ", root_path, "location_models/density_tables/"),
                density_q,
                paste0(" ", root_path, "location_models/density_tables/"),
                s,
                "_",
                density_q))
  
})
