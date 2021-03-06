## The RAINLINK package. Retrieval algorithm for rainfall mapping from microwave links 
## in a cellular communication network.## R function 'WetDryLinkApproach.R'.
## 
## Version 1.11
## Copyright (C) 2017 Aart Overeem
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program. If not, see <http://www.gnu.org/licenses/>.

#' Function for classifying wet and dry periods according to the nearby link approach. 
#' Function also prepares link data for determination of reference signal level and for 
#' computing corrected received powers. 
#' @description The received signal powers often decrease during non-rainy periods, 
#' resulting in non-zero rainfall estimates, e.g. caused by reflection of the beam or dew 
#' formation on the antennas. To prevent this rainfall overestimation a reliable 
#' classification of wet and dry periods is needed. This is also beneficial for 
#' determining an appropriate reference signal level, representative for dry weather. 
#' In order to define wet and dry periods, we assume that rain is correlated in space, and 
#' hence that several links in a given area should experience a decrease in minimum received signal 
#' level in the case of rain. A time interval is labeled as wet if at least half of the links 
#' in the vicinity (for chosen radius) of the selected link experience such a decrease. This 
#' so called nearby link approach is applied in this function. The function also prepares 
#' link data for determination of reference signal level and for computing corrected received 
#' powers. 
#' 
#' Works for a sampling strategy where minimum and maximum received signal powers
#' are provided, and the transmitted power levels are constant.
#'
#' Also works for a sampling strategy where instantaneous transmitted and received signal levels are obtained.
#' In case of instantaneous signal levels, it does not matter whether transmitted power levels vary or are constant.
#' The only requirement is that the input data for RAINLINK needs some preprocessing. See ''ManualRAINLINK.pdf''
#' for instructions. 
#'
#' The time interval does not have to be an integer but should be equidistant. The minimum time 
#' interval length in the time series is automatically computed and is employed as the time 
#' interval length.
#'
#' @param Data Data frame with microwave link data.
#' @param CoorSystemInputData Define coordinate system of input data (in case of
#' WGS84 provide NULL).
#' @param MinHoursPmin Minimum number of hours in the previous PeriodHoursPmin hours needed 
#' for computing max(P\eqn{_{\mbox{min}}}) (h).
#' @param PeriodHoursPmin Number of hours that is considered for computation of 
#' max(P\eqn{_{\mbox{min}}}) (h).
#' @param Radius Radius in wet-dry classification (km).
#' @param Step8 If TRUE step 8 in the wet-dry classification is performed, else it is not executed.
#' @param ThresholdMedian Threshold value (dB).
#' @param ThresholdMedianL Threshold value (dB km\eqn{^{-1}}).
#' @param ThresholdNumberLinks Only use data if number of available (surrounding) links is at least larger than this 
#' threshold for the time interval under consideration. The selected link is also counted.
#' @return Data frame: Should interval be considered dry for reference level.
#' determination? (0 = wet; 1 = dry)
#' @return Values F for filter to remove outliers (dB km\eqn{^{-1}} h)
#' @export WetDryNearbyLinkApMinMaxRSL
#' @examples
#' WetDryNearbyLinkApMinMaxRSL(Data=DataPreprocessed,CoorSystemInputData=NULL, 
#' MinHoursPmin=6,PeriodHoursPmin=24,Radius=15,Step8=TRUE,ThresholdMedian=-1.4, 
#' ThresholdMedianL=-0.7,ThresholdNumberLinks=3,ThresholdWetDry=2)
#' @author Aart Overeem & Hidde Leijnse
#' @references ''ManualRAINLINK.pdf''
#'
#' Overeem, A., Leijnse, H., and Uijlenhoet, R., 2016: Retrieval algorithm for rainfall mapping from microwave links in a 
#' cellular communication network, Atmospheric Measurement Techniques, 9, 2425-2444, https://doi.org/10.5194/amt-9-2425-2016.


WetDryNearbyLinkApMinMaxRSL <- function(Data,CoorSystemInputData=NULL,MinHoursPmin=6,PeriodHoursPmin=24,
Radius=15,Step8=TRUE,ThresholdMedian=-1.4,ThresholdMedianL=-0.7,ThresholdNumberLinks=3,ThresholdWetDry=2)
{
	# Determine the middle of the area over which there are data 
	# (for reprojection onto a Cartesian coordinate system)
	if (!is.null(CoorSystemInputData))
	{
		Coor <- data.frame(x = c(min(Data$XStart, Data$XEnd), max(Data$XStart, Data$XEnd)), 
		y = c(min(Data$YStart, Data$YEnd), max(Data$YStart, Data$YEnd)))
		coordinates(Coor) <- c("x", "y")
		proj4string(Coor) <- CRS(CoorSystemInputData) 
		CRS.latlon <- CRS("+proj=longlat +ellps=WGS84")
		Coor.latlon <- spTransform(Coor, CRS.lotlon)
		XMiddle <- (Coor.latlon$x[1] + Coor.latlon$x[2]) / 2
		YMiddle <- (Coor.latlon$y[1] + Coor.latlon$y[2]) / 2
	} else {
		XMiddle <- (min(Data$XStart, Data$XEnd) + max(Data$XStart, Data$XEnd)) / 2
		YMiddle <- (min(Data$YStart, Data$YEnd) + max(Data$YStart, Data$YEnd)) / 2
		CoorSystemInputData <- "+proj=longlat +ellps=WGS84"
	}
	
	# Set projection string
	projstring <- paste("+proj=aeqd +a=6378.137 +b=6356.752 +R_A +lat_0=",YMiddle,
	" +lon_0=",XMiddle," +x_0=0 +y_0=0",sep="")
	
  	# Set link IDs and time intervals
	Data$ID <- as.character(Data$ID)
   	IDLink <- unique(Data$ID)
   	N_links <- length(IDLink)
	t <- sort(unique(Data$DateTime))
	N_t <- length(t)
	
	# Make numeric representation of time in seconds from an arbitrary origin
	t_sec <- as.numeric(as.POSIXct(as.character(t), format = "%Y%m%d%H%M"))
	
	# Determine time interval length (in seconds)
	dt <- min(diff(t_sec))
	
	#Determine time indices for each entry
	t_ind <- rep(NA, length(Data$DateTime))
	for (i in 1 : N_t)
	{
		ind <- which(Data$DateTime == t[i])
		t_ind[ind] <- i
	}
	
	# Initialize arrays and vectors
	PminLink <- array(NA, c(N_t, N_links))
	array_ind <- array(NA, c(N_t, N_links))
   	XStartLink <- rep(NA, N_links)
	YStartLink <- rep(NA, N_links)
	XEndLink <- rep(NA, N_links)
	YEndLink <- rep(NA, N_links)
	LengthLink <- rep(NA, N_links)
	
	# Loop over all links for coordinate transformation and putting data in an array
   	for (p in 1 : N_links)
   	{
		# Find indices corresppnding to this link
		Cond <- which(Data$ID == IDLink[p])
		
		#Convert coordinates to a system in km, centered on the area covered by the links
		Coor <- data.frame(x = c(Data$XStart[Cond[1]], Data$XEnd[Cond[1]]), 
		y = c(Data$YStart[Cond[1]], Data$YEnd[Cond[1]]))
		coordinates(Coor) <- c("x", "y")
		proj4string(Coor) <- CRS(CoorSystemInputData) 
		CRS.cart <- CRS(projstring)
		Coor.cart <- spTransform(Coor, CRS.cart)
		XStartLink[p] <- Coor.cart$x[1]  # Easting (in km)
		YStartLink[p] <- Coor.cart$y[1]  # Northing (in km)
		XEndLink[p] <- Coor.cart$x[2]  # Easting (in km)
		YEndLink[p] <- Coor.cart$y[2]  # Northing (in km)
		
		LengthLink[p] <- Data$PathLength[Cond[1]] 
		
		# Store data from the considered link in an array
		PminLink[t_ind[Cond],p] <- Data$Pmin[Cond]
		array_ind[t_ind[Cond], p] <- Cond
	}
	
	# Initialize arrays
	PminLink_max <- array(NA, c(N_t, N_links))
	DeltaP <- array(NA, c(N_t, N_links))
	DeltaPL <- array(NA, c(N_t, N_links))
	ind_PrevPeriod <- rep(1, N_t)
	for (i in 2 : N_t)
	{
		# Determine index of time at most PeriodHoursPmin before current time interval
		int.ind = which(t_sec[ind_PrevPeriod[i - 1] : (i - 1)] > (t_sec[i] - PeriodHoursPmin * 3600))
		if (length(int.ind) > 0) {
			ind_PrevPeriod[i] <- min(int.ind) + ind_PrevPeriod[i - 1] - 1
			
			# Compute the time for which valid data are available, and check if this is sufficient
			t_valid <- colSums(!is.na(PminLink[ind_PrevPeriod[i] : i, ])) * dt
			links_valid <- which(t_valid >= (MinHoursPmin * 3600))
			if (length(links_valid) > 0)
			{
				for (j in links_valid)
				{
					# Compute maximum of Pmin over previous PeriodHoursPmin
					PminLink_max[i, j] <- max(PminLink[ind_PrevPeriod[i] : i, j], na.rm = TRUE)
				}
				
				# Compute Delta P and Delta P_L
				DeltaP[i, links_valid] <- PminLink[i, links_valid] - PminLink_max[i, links_valid]
				DeltaPL[i, links_valid] <- DeltaP[i, links_valid] / LengthLink[links_valid]
			}
		}
	}
	
	# Initialize dry and F vectors
	dry_vec <- rep(NA, length(Data$DateTime))
	F_vec <- rep(NA, length(Data$DateTime))
	for (i in 1 : N_links)
	{
		# Compute distances
		Distance1 <- sqrt( (XStartLink[i]-XStartLink)^2 + (YStartLink[i]-YStartLink)^2 )
		Distance2 <- sqrt( (XEndLink[i]-XStartLink)^2 + (YEndLink[i]-YStartLink)^2 ) 	
		Distance3 <- sqrt( (XStartLink[i]-XEndLink)^2 + (YStartLink[i]-YEndLink)^2 )
		Distance4 <- sqrt( (XEndLink[i]-XEndLink)^2 + (YEndLink[i]-YEndLink)^2 ) 
		SelectDist <- which(Distance1 < Radius & Distance2 < Radius & Distance3 < Radius & 
		Distance4 < Radius )
		
		# Loop over all time intervals to compute medians and F values
		medianDeltaP <- rep(NA, N_t)
		medianDeltaPL <- rep(NA, N_t)
		for (j in 1 : N_t)
		{
			# Check if enough links are available for median and F computation
			if (sum(!is.na(DeltaP[j, SelectDist])) >= ThresholdNumberLinks)
			{
				medianDeltaP[j] = median(DeltaP[j, SelectDist], na.rm = TRUE)
				medianDeltaPL[j] = median(DeltaPL[j, SelectDist], na.rm = TRUE)
				F[j] <- sum(DeltaPL[ind_PrevPeriod[j] : j, i] - 
				medianDeltaPL[ind_PrevPeriod[j] : j], na.rm = TRUE) * dt / 3600
			}
		}
		
		# Set dry indicator variable
		dry  <- rep(0, N_t)
		dry[medianDeltaP >= ThresholdMedian | medianDeltaPL >= ThresholdMedianL] <- 1
		dry[is.na(medianDeltaP) | is.na(medianDeltaPL)] <- NA
		
		# Perform step 8 if desired
		if (Step8)
		{
			ind_wet <- which(dry == 0 & DeltaP[, i] < (-1 * ThresholdWetDry))
			int_dry <- dry
			dry[ind_wet[ind_wet > 1] - 1] <- 0
			dry[ind_wet[ind_wet > 2] - 2] <- 0
			dry[ind_wet[ind_wet < length(dry)] + 1] <- 0
			dry[is.na(int_dry)] <- NA
		}
		
		# Map arrays of dry and F to vectors corresponding to input data frame
		dry_vec[array_ind[!is.na(array_ind[, i]), i]] <- dry[!is.na(array_ind[, i])]
		F_vec[array_ind[!is.na(array_ind[, i]), i]] <- F[!is.na(array_ind[, i])]
	}
	# Set return data frame
	return_value <- data.frame(Dry = dry_vec, F = F_vec)
	return(return_value)

}
