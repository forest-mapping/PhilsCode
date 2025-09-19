library(sf)
library(terra)
library(tidyverse)

# data_path = file.path("/home/rstudio/data/Rayonier_lidar/")
# raster_list <- st_read(dsn = file.path(data_path, "imagery"))
# 
# 
# raster <- rast("MOD11A2_2017-07-12.LST_Day_1km.tif")
# 
# raster1 <- a
# raster2 <- b
# class(a)


#terra::crs() returns detailed projection information for SpatRaster objects.
#sf::st_crs() is used to extract CRS information from spatRaster objects. This approach prints the CRS in a format that is a bit more compact and easy to read than the output of the crs() function
#Raster data are reprojected using the project() function from the terra package.
#By default, the project() function uses bilinear interpolation appropriate for continuous data like elevation and temperature but not for numerical class codes like land cover data
#compareGeom() function can be used to confirm that the two rasters have the exact same geometry, with identical extents, numbers of rows and columns, coordinate reference systems, cell sizes, and origins.
#st_set_crs function is used with the EPSG code for geographic coordinates
#It is also possible to assign coordinate reference systems to raster data using the crs() function in the terra() package.
#it can be assigned a coordinate system by specifying an EPSG code or assigning the CRS from another raster dataset.

reproject_align_raster<- function(rast, ref_rast=NULL, desired_origin, desired_res, desired_crs, method= "bilinear",tol_origin=1e-04){
  #Set parameters based on ref rast if it was supplied  
  if (!is.null(ref_rast)) {
    desired_origin<- terra::origin(ref_rast) #Desired origin
    desired_res<- terra::res(ref_rast) #Desired resolution
    desired_crs<- terra::crs(ref_rast) #Desired crs
  }
  if(length(desired_res)==1){
    desired_res<- rep(desired_res,2)}
  
  if(identical(terra::crs(rast), desired_crs) & identical(terra::origin(rast), desired_origin) & identical(desired_res, terra::res(rast))){
    message("raster was already aligned")
    return(rast)} #Raster already aligned
  
  if(identical(terra::crs(rast), desired_crs)){
    rast_orig_extent<- terra::ext(rast)
  }else{
    rast_orig_extent<- terra::ext(project(x = rast, y = desired_crs))} #reproject extent if crs is not the same
  var1<- floor((rast_orig_extent$xmin - desired_origin[1])/desired_res[1])
  new_xmin<-desired_origin[1]+ desired_res[1]*var1 #Calculate new minimum x value for extent
  var2<- floor((rast_orig_extent$ymin - desired_origin[2])/desired_res[2])
  new_ymin<-desired_origin[2]+ desired_res[2]*var2 #Calculate new minimum y value for extent
  n_cols<- ceiling((rast_orig_extent$xmax-new_xmin)/desired_res[1]) #number of cols to be in output raster
  n_rows<- ceiling((rast_orig_extent$ymax-new_ymin)/desired_res[2]) #number of cols to be in output raster
  new_xmax<- new_xmin+(n_cols*desired_res[1]) #Calculate new max x value for extent
  new_ymax<- new_ymin+(n_rows*desired_res[2]) #Calculate new max y value for extent
  rast_new_template<- rast(xmin=new_xmin, xmax =new_xmax,  ymin=new_ymin, ymax= new_ymax, resolution=desired_res, crs= desired_crs) #Create a blank template raster to fill with desired properties
  if(sqrt(sum(desired_origin - origin(rast_new_template))^2) > tol_origin){
    message("desired origin does not match output origin")
    stop()} #Throw error if origin doesn't match
  
  # needs revision for spat_rast
  if(identical(terra::crs(ref_rast),terra::crs(rast))){
    rast_new<- resample(x=rast, y=rast_new_template, method = method)} else{
      rast_new<- project(x=rast, y=rast_new_template, method = method)      ## Using cluster with 35 nodes
    } #Use projectRaster if crs doesn't match and resample if they do
  if(sqrt(sum(desired_origin - origin(rast_new))^2) > tol_origin){
    message("desired origin does not match output origin")
    stop()} #Throw error if origin doesn't match
  return(rast_new)
}
