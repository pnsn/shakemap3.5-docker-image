#!/usr/bin/perl

#********** dam_calc - the bridge damage probability calculator                   ****
#********** by: Jay LaBelle (2004)                                                ****

# 1.2 modified to combine hazus and UW probabilities into the same output
#   file and sort on UW probability  12/20/04  SDM

# 1.3 modified to add psa03 to the output list 6/07/2005 SDM

#***** General Program documentation *************************************************
# USAGE:
#  The program can be run in 2 ways.  One way is in standalone mode, where dam_calc
# will simply analyze the bridge inventory it is fed against the grid file that it is 
# fed.  The command line parameters for this mode are:
# ./dam_calc <bridge_inventory_file> <grid_file>
#  In this mode, two files will be produced in the directory from which the program 
# was executed. (dam_prob.hazus and dam_prob.uw).  These files contain the damage 
# probabilities calculated in the two different manners.
#  The second way to run dam_calc is through Shakemap.  In this mode, dam_calc should
# be added to the Shakemap execution list in the 'shake.conf' file in the /config
# directory of the Shakemap tree.  The 'nodep' Shakemap option should be used for 
# executing dam_calc.  Shakemap will then execute dam_calc passing the '-event' flag
# and the event ID.  To use this mode, the file locations and paths need to be 
# configured later on in this script. (Text search for 'FILENAMES/PATHS' to see where)
# 
# REQUIREMENTS:
# - dam_calc needs Perl, obviously.  
# - It also requires the Perl module 'Math::CDF' to 
# be accessible through the normal Perl means.  (The interpretor needs to be able to 
# find it.)
# - dam_calc needs the UNIX 'sort' command.  The path and flags for 'sort' need to be
# configured in this script also.  (Text search for 'SORT CONFIG' in this script to 
# find it.)
# - inventory file: This is the Washington State Bridge Inventory.  (Really any 
# inventory file would work as long as it has the expected format.)
# - dam_calc needs a grid file from Shakemap.
# 
# OUTPUT:
# dam_calc produces two files for each run, labelled differently depending on which 
# mode produced them.  If in standalone mode, ./dam_prob.hazus and ./dam_prob.uw will 
# be created.  If in 'Shakemap' mode, then the files created will be called something 
# based on the event ID of the event, and will be placed in the locations specified
# by the path variables spoken about before.
#*************************************************************************************

#*************************************************************************************
#**** FUNCTION DOCUMENTATION  ********************************************************
#*************************************************************************************

#***** calc_accels() *****************************************************************
# USAGE:
#   ($br_psa03, $br_psa10, $br_pga, $gr_lat, $gr_lon) = calc_accels($br_ref);
#
# PARAMETERS: $br_ref is a reference (like a pointer) to a bridge array.  This bridge 
#   array contains all of the information about the bridge.
#
# RETURN VALUES: $br_psa03, $br_psa10, $br_pga are psa03. psa10, and pga for the 
#   bridge.  These values aren't updated in the bridge array by this function.
#   It is up to the calling function to change the bridge array.  
#   $gr_lat, $gr_lon are the latitude and longitude of the last point used in the
#   calculation.  These values don't make sense any more, but are still returned 
#   because they were used in development and haven't been removed yet.
#
# DESCRIPTION:
# Calculates the ground motion parameters at the location of the specific bridge 
# passed to it.  If the bridge lies between 4 points, (inside the quadrilateral 
# limited by 4 grid points,) it uses all 4 points to calculate a weighted average 
# of the ground motion parameters at the location of the bridge.  The falloff of the
# weighting is described by the coefficient in the "CONFIGURABLE CONSTANTS" section
# below.  If the bridge lies directly between 2 points, or is on the edge of the 
# Shakemap area, it uses only 2 points to calculate the average.  If it is exactly 
# coincident with a point, it uses only that point and no average is calculated.
# This function calls other functions to perform these calculations.
# ************************************************************************************

#***** find_grids() ******************************************************************
# USAGE:
#   @boundpts = find_grids($bridge_ref);  
# PARAMETERS:
#   $br_ref is a reference (like a pointer) to a bridge array.  This bridge 
# array contains all of the information about the bridge.
# RETURN VALUES:  
#   @boundpts = ($sw, $nw, $se, $ne)
# DESCRIPTION:
#   This function uses 2 recursive algorithms to find the grid points that surround 
# the bridge.  We know that the grid points are sorted in order of latitude and then 
# longitude.  That is to say that latitude takes precedence, and then for all points of
# the same latitude, the points are sorted by longitude.  This enables us to search 
# first for the points whose latitude is immedately adjacent to the bridge, and then
# search for the longitude points amongst this set.  This is how this function works.
# The function divides the gridpoint set in half by latitude, and then calls itself 
# using the half that contains the desired points.  In this fashion, the algorithm 
# execution time scales proportionally to the base-2 log of the total number of grid 
# points.  The process is then repeated using the longitude.  The result is 1,2, or 4 
# grid points that surround the bridge.
#
#   Note: If nw or ne == 0, then the bridge matches the latitude of grid point exactly.  
# If se and sw are the same, or ne and nw are the same, then the bridge matches the 
# longitude of a grid point exactly.  If nw or ne == 0 and se and sw are the same, 
# then the bridge is on a grid point.
#
#*************************************************************************************

#***** lat_search() ******************************************************************
# USAGE (example):
#   ($beg, $end) = lat_search($beg, $end, $bridge);
# PARAMETERS:
#   $beg and $end are the beginning and ending indices of the segment of the grid point
# array to be searched.  $bridge is the reference to the bridge in question.
# RETURN VALUES:
#   $beg and $end are the beginning and ending indices of the segment of the grid point
# array that contains the set of all grid points at the latitudes immediately adjacent 
# to the bridge.  (The row above and below, or the row the bridge is on.)
# DESCRIPTION:
#   Uses a recursive algorithm to find the grid points at the latitudes immediately 
# adjacent to the bridge.  (The row above and below, or the row the bridge is on.)
#*************************************************************************************

#***** lon_search() ******************************************************************
# USAGE (example):
#   ($sw_pt, $se_pt) = lon_search($beg, $end, $bridge);
# PARAMETERS:
#   $beg and $end are the beginning and ending indices of the segment of the grid point
# array to be searched.  $bridge is the reference to the bridge in question.
# RETURN VALUES:
#   $beg and $end are the beginning and ending indices of the segment of the grid point
# array that contains the set of all grid points at the longitudes immediately adjacent 
# to the bridge.  (The column east and west, or the column the bridge is on.)
# DESCRIPTION:
#    Uses a recursive algorithm to find the grid points at the longitudes immediately 
# adjacent to the bridge.  (The column east and west, or the column the bridge is on.)
# Since this is usually called with the subset of grid points that are immediately 
# north and south of the bridge, this effectively returns indices that are either the 
# same or differing by 1.  This is called twice in most cases, once on the northern row
# and once on the southern row, to give up to 4 points total.
#*************************************************************************************

#***** usage() ***********************************************************************
# USAGE:
#   usage()
# PARAMETERS:
#   none.
# RETURN VALUES:
#   none.
# DESCRIPTION:
#   Prints out usage info if the command line parameters don't make sense.
#*************************************************************************************

#***** parse_gridfile() **************************************************************
# USAGE:
#   parse_gridfile();
# PARAMETERS:
#   none
# RETURN VALUES:
#   none
# DESCRIPTION:
#   Reads the grid file, sets the global variables that are associated with the 
# metainfo in the grid file, and loads the grid point arrays.  Also checks to make sure
# that the grid point array is loaded with good data.  Keeps a count of number of grid 
# points read. (global var)
#*************************************************************************************

#***** parse_inventory() *************************************************************
# USAGE:
#   parse_inventory();
# PARAMETERS:
#   none
# RETURN VALUES:
#   none
# DESCRIPTION:
#   Reads the bridge inventory file, loads the bridge arrays.  Checks to make sure 
# that the bridge data is good.  Keeps a count of number of bridges read. (global var)
#*************************************************************************************

#***** UW_prob_calc() ****************************************************************
# USAGE:
#   $UWPd = UW_prob_calc($br_year, $br_span, $br_psa03);
# PARAMETERS:
#   $br_year, $br_span, $br_psa03 are all bridge parameters that are calculated or 
# taken directly from the inventory.  They are all stored in the bridge array, but 
# for the sake of this example, (and clarity elsewhere in the code,) have been 
# renamed/equated. 
# RETURN VALUES:
#   $UWPd is the probability of this bridge being damaged.  It is a floating point
# value between 0 and 1.
# DESCRIPTION:
#   This function calculates the probability of bridge damage per the method shown
# in the paper by Ranf and Eberhard.
#*************************************************************************************

#***** HAZUS_prob_calc() *************************************************************
# USAGE:
#   $HAZUSPd = HAZUS_prob_calc($br_ref, $br_psa03, $br_psa10, $br_pga);
# PARAMETERS:
#   $br_ref, $br_psa03, $br_psa10, $br_pga are all bridge parameters that are calculated 
# or taken directly from the inventory.  They are all stored in the bridge array, but 
# for the sake of this example, (and clarity elsewhere in the code,) have been 
# renamed/equated.  $br_ref is the reference to the bridge array in question, $br_psa03, 
# $br_psa10, are spectral accelerations, and $br_pga is the peak ground acceleration of
# the bridge in question.
# RETURN VALUES:
#   $HAZUSPd is the probability of this bridge being damaged calculated.
# This value is a floating point value between 0 and 1.
# DESCRIPTION:
#   This method is described in the HAZUS documentation and a comparison with 
# the UW method is in the paper by Ranf and Eberhard. 
#*************************************************************************************

#***** HAZUS_classify() *************************************************************
# USAGE:
#   $br_htype = HAZUS_classify($br_ref, $br_length);
# PARAMETERS:
#   $br_ref is the reference to the bridge array in question, and $br_length is a value
# used by the HAZUS classification system that is the NBI length if it exists, or the
# length paramater from the Washington State Bridge Inventory.
# RETURN VALUES:
#   $br_htype is the HAZUS bridge type.  (Integer)
# DESCRIPTION:
#   Classifies the bridge per the standard HAZUS bridge classification method.  Does 
# not store the classification in the bridge array.  This is handled by the calling 
# function.  This was derived from R.T. Ranf's code.
#
#*************************************************************************************

#*************************************************************************************
#***** DATA/VARIABLE DOCUMENTATION ***************************************************
#*************************************************************************************

#***** BRIDGE ARRAY INDICES DOCUMENTATION:  
# The bridge data is stored in the following manner: Each bridge has it's info stored 
# in an array of the type described by the indices below.  There is another array that
# contains references (like pointers in C) to each of these arrays.  All of these 
# arrays are global.  This was done because nearly every function needs them anyway.
#
# *** What all the array indices point to: 
#
#0  : Internal index 
#1  : Latitude
#2  : Longitude
#3  : Year
#4  : Bridge Number
#5  : Span Type (NBI class)
#6  : Bridge Name
#7  : Material
#8  : DOT Bridge ID
#9  : Length
#10 : NBILength
#11 : Max Span
#12 : Unused
#13 : Unused
#14 : HAZUS bridge classification
#15 : psa03
#16 : grid point latitude (only the last point considered in the cell that contains the bridge -- legacy)
#17 : grid point longitude (see above comment)
#18 : peak ground acceleration (PGA)
#19 : peak spectral accel. (1 Hz) (psa10)
#20 : UW damage probability
#21 : HAZUS damage probability
#*******************************************************

#***** GRID POINT ARRAY DOCUMENTATION: What all the array indices point to.
#
#0  : Latitude
#1  : Longitude
#2  : PGA
#3  : Values unused in this program.
#4  : Values unused in this program.
#5  : PSA03
#6  : PSA10
#7  : PSA30
#********************************************************************

#***************************************************************
#***** BEGINNING OF THE ACTUAL CODE ****************************
#***************************************************************

use strict;
require Math::CDF;

# *****************************************************
# CONFIGURABLE CONSTANTS.  These shouldn't have to be changed, with the possible
# exception of the $sort_command variable.  
# NOTE: There are more configurable options farther down in this file.  They
# aren't really constants in the traditional sense though, so they are separate.
# *****************************************************

   # *****Configurable option*****************************
   # $sort_command contains the command to which an unsorted bridge damage probability 
   # list is piped.  This can be changed, but this should work for most FreeBSD or Linux
   # systems.  The '-r' inverts the sort order, so that the highest probability is listed
   # first.
   # *****************************************************

   # ***** SORT CONFIG *****

   our $sort_command = '/bin/sort -r';

   #Bridge type curve coefficients for the UW method.  See UW method docs for more 
   #information.
   # 
   # These should not be changed unless you know what you are doing.  These constants
   # directly effect how the damage probability is calculated.
   #
   # These variables are set as they are to make the algorithm appear more similar
   # to the algorithm described by R.T. Ranf in his Matlab code.

   our @uw_coefficients = (90, 0.60, 140, 0.6, 160, 0.6, 60, 0.6, 55., 0.6);
   our $lam1 = $uw_coefficients[0];
   our $xi1 = $uw_coefficients[1];
   our $lam2 = $uw_coefficients[2];
   our $xi2 = $uw_coefficients[3];
   our $lam3 = $uw_coefficients[4];
   our $xi3 = $uw_coefficients[5];
   our $lam4 = $uw_coefficients[6];
   our $xi4 = $uw_coefficients[7];
   our $lam5 = $uw_coefficients[8];
   our $xi5 = $uw_coefficients[9];
   our @uw_years = (1940, 1975);   #separation years, these are the years that separate 
                                   #the eras in the UW classification scheme.

   our $INTERP_POWER = -2;         #Power to which the distance between bridge location 
                                   #and grid point is raised to calculate a weighting 
                                   #for the weighted average.  (-2 implies an inverse
                                   #square relationship.)

   our $HAZUS_YEAR = 1975;         #Parameters used in the HAZUS algorithm.  (See HAZUS
                                   #docs for more information.)
   our $HAZUS_SD = 0.6;            #HAZUS standard deviation
   our $LAT_BUF = 0.03;            #LAT_BUF and LON_BUF are in degrees.  These values
   our $LON_BUF = 0.03;            #specify the amount to be subtracted from the usable
                                   #map boundries in the grid.xyz header line.
				   #They are here because rounding errors sometimes 
				   #produce a discrepancy between the boundry in the 
				   #header and the grid points that exist in the file
				   #which causes the search algorithms to fail.  0.03 in 
				   #both of these parameters is fairly liberal, but it
				   #should be sufficient for even very large events.
				   #on the Ml=4.0 event that presented this issue, 
				   #the rounding error as less than 0.01.  Manual 
				   #adjustment of the values in the header of grid.xyz
				   #fixed the problem.  In all cases, these manual 
				   #adjustments were less than 0.01 degrees.

#*********************************************************************************
#End Constants
#*********************************************************************************

#*****GLOBAL DECLARATIONS
# Includes the arrays that hold either values or references for the bridges.
#*****

#array of references to bridge arrays

our @bridges = ();
# array of references to grid arrays

our @shake_pts = ();

#counters of various things  

our $in_count = 0;
our $out_count = 0;
our $grids_in = 0;
our $grids_used = 0;

#mode of operation, from command line

our $method = '';

#The array that holds the metaline data from the header of the gridfile

our @map_params = ();

#filenames/paths -- defined further down in the script.  
#The definitions are user configurable, and should be configured appropriately.

our $br_inv_file = '';
our $grid_file = '';
our $uw_out_file = '';
our $hazus_out_file = '';

#event ID -- from command line if 'SM' method is used.

our $evid = '';

#File/IO handles

our $INV_HDL = 0;
our $GRID_HDL = 0;
our $UW_OUT = 0;
our $HAZUS_OUT = 0;

#Boundry lines from the grid file

our $west_bdry = 0;
our $east_bdry = 0;
our $north_bdry = 0;
our $south_bdry = 0;

#Counter for number of bridges processed.

our $processed = 0;
#*****************************************

#****************************************************************************
# Main part of the program.  Calls the other functions and loops.
#****************************************************************************

#***************************
# Parse the command line parameters (this section can be optimized)
#***************************

if ($ARGV[0] eq '-event') {    #being run from Shakemap
  if (scalar(@ARGV) != 2) {
    usage();
    die();
  }
  else {
    $method = 'SM';         #Shakemap
    $evid = $ARGV[1];
  }
}
else {                          #being run standalone
  if (scalar(@ARGV) != 2) {
  usage();
  die();
  }
  else {
    $method = 'SA';         #Standalone
  }
}

#***********************
#*** FILENAMES/PATHS: these can be changed by the user as needed.
#***********************

if ($method eq 'SM') {
  $br_inv_file = $ENV{SHAKE_HOME}.'/lib/dam_calc/br_inv.dat';
  $grid_file = $ENV{SHAKE_HOME}.'/data/'.$evid.'/output/grid.xyz';
  $uw_out_file = $ENV{SHAKE_HOME}.'/data/'.$evid.'/genex/web/shake/'.$evid.'/'.$evid.'_dam_prob.uw';
  $hazus_out_file = $ENV{SHAKE_HOME}.'/data/'.$evid.'/genex/web/shake/'.$evid.'/'.$evid.'_dam_prob.hazus';
 }
elsif ($method eq 'SA') {
  $br_inv_file = $ARGV[0];
  $grid_file = $ARGV[1];
  $uw_out_file = './dam_prob.uw';
  $hazus_out_file = './dam_prob.hazus';
}
else {
  die "\nIrrecoverable error that should never happen.  Can't determine where any of the inputs should come from.";
}
#**********************

#******************
#**  Open the input files and output files.  (open the output files to test if they can be opened/written to)
#******************

open(INV_HDL, "<", $br_inv_file) or die "\nError opening inventory file.", $br_inv_file;
open(GRID_HDL, "<", $grid_file) or die "\nError opening grid file.", $grid_file;
open(UW_OUT, "| $sort_command -r > $uw_out_file") or die "\nError opening pipe to sort for the UW output file.", $uw_out_file;
# open(HAZUS_OUT, "| $sort_command -r > $hazus_out_file") or die "\nError opening pipe to sort for the HAZUS output file.", $hazus_out_file;

#******************

#******************
#** Read and store the input
#******************

parse_gridfile();     #Parse the gridfile, read in the meta line and store the grid lines in RAM
if ($grids_used < 4) {
    print "Exiting. Too few lines read from $grid_file\n";
    print "Are you sure your grid file contains eight columns of data?\n";
    exit 0;
}
close(GRID_HDL);
parse_inventory();
close(INV_HDL);

#***************************



#**********************TEST CODE*******************************
#foreach my $br_ref (@bridges)  {
#  print "\n",join(":",@{$br_ref});
#}
#print "\n Last array index: (scalar/dollar-pound)",scalar(@bridges),"/",$#bridges,"\n";
#**************************************************************

#This is where the actual calulation of the damage probability occurs.

foreach my $br_ref (@bridges)  {
  my $br_psa03 = 0;
  my $br_psa10 = 0;
  my $br_pga = 0;
  my $gr_lat = 0;
  my $gr_lon = 0;
  my $br_span = 0;
  my $br_year = 0;
  my $br_matl = 0;
  my $br_des = 0;
  my $br_len = 0;
  my $br_nbilen = 0;
  my $br_length = 0;
  my $br_maxspan = 0;
  my $br_length = 0;
  my $UWPd = 0;
  my $HAZUSPd = 0;

  $br_year = @{$br_ref}[3];  #These are here mostly to make parts of the code more clear.  See the table at the top for more information about what all these arrays are.
  $br_span = @{$br_ref}[5];  #note -- span here is the span type, not the length of the bridge.  Not all of these are used here.  Their scope is local.
  $br_len = @{$br_ref}[9];
  $br_nbilen = @{$br_ref}[10];
  $br_maxspan = @{$br_ref}[11];
  $br_matl = @{$br_ref}[7];
  $br_des = @{$br_ref}[5];

#*****
# This following section is to deal with bad bridge data, or data outside of the Shakemap region.  It sets latitude and longitude in the bridge array to 0 if the 
# data from the inventory was wierd or if the bridge was outside of the Shakemap region.  This is later used to determine if the bridge should be processed.
# If dam_calc.pl is run on an event where the shakemap is wholly outside of Washington, *every* bridge lat. and lon. is set to 0.  No bridges will be processed,
# and output will be generated that says so.
#*****

  if ((@{$br_ref}[1] < $south_bdry) || (@{$br_ref}[1] > $north_bdry) || (@{$br_ref}[2] > $east_bdry) || (@{$br_ref}[2] < $west_bdry)) {  
    $gr_lat = 0;
    $gr_lon = 0;
    $br_psa03 = 0;
    $br_pga = 0;
    $br_psa10 = 0;
    $UWPd = 0;
    $HAZUSPd = 0;
    @{$br_ref}[1] = 0;
    @{$br_ref}[2] = 0;
    @{$br_ref}[14] = 0;  #Hazus bridge type.
  }
  else {
    ($br_psa03, $br_psa10, $br_pga, $gr_lat, $gr_lon) = calc_accels($br_ref);
    if ($br_pga < 0) {    #Bad bridge data -- probably outside the grid area.
      $gr_lat = 0;
      $gr_lon = 0;
      $br_psa03 = 0;
      $br_pga = 0;
      $br_psa10 = 0;
      $UWPd = 0;
      $HAZUSPd = 0;
      @{$br_ref}[1] = 0;
      @{$br_ref}[2] = 0;
      @{$br_ref}[14] = 0;  #Hazus bridge type.
      goto(RECORD);        #skip the bridge calcs.  The data was bad anyway.
    }


    #TEST CODE -- outputs the results of the bridge analysis here if you want to for some reason.  Note that the last two parameters will be meaningless as they are now 
    #legacy code.
    #print "\nAccels: ", join(":",$br_psa03, $br_psa10, $br_pga, $gr_lat, $gr_lon);
    #END TEST CODE

    $processed = $processed + 1;
    $UWPd = UW_prob_calc($br_year, $br_span, $br_psa03);
    
    $HAZUSPd = HAZUS_prob_calc($br_ref, $br_psa03, $br_psa10, $br_pga);     #insert these variables here
  }
RECORD: 
  @{$br_ref}[15] = $br_psa03;                                               #add these values to the bridge array: $br_psa03, $gr_lat, $gr_lon, $UWPd, $HAZUSPd
  @{$br_ref}[16] = $gr_lat;                                                 #These values aren't used any more. ($gr_lat and $gr_lon).
  @{$br_ref}[17] = $gr_lon;                                                 #They are still there though to avoid confusion.
  @{$br_ref}[18] = $br_pga;                                                 #See the description of the bridge array at the beginning of the script.
  @{$br_ref}[19] = $br_psa10;
  @{$br_ref}[20] = $UWPd;
  @{$br_ref}[21] = $HAZUSPd;
  
}

#These 2 lines print the output file headers.  These headers contain the column labels only.
print UW_OUT "\nUW_Pd, HAZUS_Pd, br_psa03, DOTID,  BRName, BRNum, BRLat, BRLon";
# print HAZUS_OUT "\nPd,DOTID,BRName,BRNum,BRLat,BRLon";

#*****
#Inside the 'foreach' loop, the commented 'print' lines with different output format 
#were used to compare data against the Eberhard/Ranf Matlab code output.  These shouldn't
#be needed for any other reason.  They are left there, however, in case they need to be used.
#Note that if they are to be used, that the other output lines should be commented instead.
#*****

foreach my $bridge (@bridges) {
  $| = 1;  # unbuffers output
  if ((@{$bridge}[1] == 0) || (@{$bridge}[2] == 0) || (@{$bridge}[3] == 0)) {
    if ($method eq 'SA') {
      printf(UW_OUT "\n%.5f,%.5f,%.2f,%s,%s,%s,%.5f,%.5f",@{$bridge}[20], @{$bridge}[21],  @{$bridge}[15], @{$bridge}[8], @{$bridge}[6], @{$bridge}[4], @{$bridge}[1], @{$bridge}[2]);
      #print UW_OUT join(":",@{$bridge}[20],@{$bridge}[1],@{$bridge}[2],@{$bridge}[15],@{$bridge}[19],@{$bridge}[18],@{$bridge}[3],@{$bridge}[5]), "\n";
#      printf(HAZUS_OUT "\n%.5f,%s,%s,%s,%.5f,%.5f",@{$bridge}[21], @{$bridge}[8], @{$bridge}[6], @{$bridge}[4], @{$bridge}[1], @{$bridge}[2]);
      #print HAZUS_OUT join(":",@{$bridge}[21],@{$bridge}[1],@{$bridge}[2],@{$bridge}[15],@{$bridge}[19],@{$bridge}[18],@{$bridge}[3],@{$bridge}[14]), "\n";
    }
  }
  else {
    printf(UW_OUT "\n%.5f,%.5f,%.2f,%s,%s,%s,%.5f,%.5f",@{$bridge}[20], @{$bridge}[21], @{$bridge}[15], @{$bridge}[8], @{$bridge}[6], @{$bridge}[4], @{$bridge}[1], @{$bridge}[2]);
#    printf(HAZUS_OUT "\n%.5f,%s,%s,%s,%.5f,%.5f",@{$bridge}[21], @{$bridge}[8], @{$bridge}[6], @{$bridge}[4], @{$bridge}[1], @{$bridge}[2]);
    #print UW_OUT join(":",@{$bridge}[20],@{$bridge}[1],@{$bridge}[2],@{$bridge}[15],@{$bridge}[19],@{$bridge}[18],@{$bridge}[3],@{$bridge}[5]), "\n";
    #print HAZUS_OUT join(":",@{$bridge}[21],@{$bridge}[1],@{$bridge}[2],@{$bridge}[15],@{$bridge}[19],@{$bridge}[18],@{$bridge}[3],@{$bridge}[14]), "\n";
    $out_count = $out_count + 1;
  }
}

#*****TEST CODE -- for verifying that grid points were read properly.  Dumps the grid point data structure to STDOUT.
#foreach my $gr_pt (@shake_pts)  {
#  print "\n", join(":",@{$gr_pt});
#}
#*****END TEST CODE

print "\nBridges in: ", $in_count, " Bridges processed: ", $out_count, " Grid points input: ", $grids_in, " Grid points used: ", $grids_used, " South bdry: ", $south_bdry, " North bdry: ", $north_bdry, " West bdry: ", $west_bdry, " East bdry: ", $east_bdry, "\n";
close(UW_OUT);
# close(HAZUS_OUT);


sub calc_accels {                 #Calculates a weighted average of the 4 (or less) gridpoints surrounding the bridge
  my $bridge_ref = shift(@_);
  my @bridge = @{$bridge_ref};
  my $br_lat = @bridge[1];
  my $br_lon = @bridge[2];
  my @boundpts = (0,0,0,0);
  my @w_ave_pts = ();
  my $wav_denom = 0;
  my $wa_psa03 = 0;
  my $wa_psa10 = 0;
  my $wa_pga = 0;
  my $numpts = 0;
  my $dist = -1;


#*********TEST CODE****  Outputs boundries read from the grid file.  
#  $| = 1;
#  print "\n shakemap bdry pts: ", $north_bdry, $south_bdry, $west_bdry, $east_bdry;
#
#*********END TEST CODE


  @boundpts = find_grids($bridge_ref); 


#*********TEST CODE**** Outputs the points that surround the bridge. (Not the same as the grid file boundries spoken about above.)
#
#  print "\n boundry points ", join(":", @boundpts);
#
#*********END TEST CODE


  foreach my $grid (@boundpts) {
    if ($grid == -100) {   #Bridge data was bad.  Skip this bridge.  Returning -100 for pga means skip.
      $wa_pga = -100;
      goto(RSTATEMENT);
      }
    if ($grid != -1) {                                                                           #if $grid == -1, it's because not all 4 boundry points were needed. ignore.
      $dist = sqrt(($br_lat - @{@shake_pts[$grid]}[1])**2 + ($br_lon - @{@shake_pts[$grid]}[2])**2);
      if ($dist == 0) {                                                                          #the grid was right on -- just return it.
	return(@{@shake_pts[$grid]}[5], @{@shake_pts[$grid]}[1], @{@shake_pts[$grid]}[2]);
      }
      else {
	push(@w_ave_pts, $grid);                    #push the array index on to this array for later calculation of the weighted average
	$numpts = $numpts + 1;
      }
    }
  }
  foreach my $point (@w_ave_pts) {
    $dist = sqrt(($br_lat - @{@shake_pts[$point]}[1])**2 + ($br_lon - @{@shake_pts[$point]}[2])**2);      #calculate the denominator for the weighted average
    $wav_denom = $wav_denom + ($dist**$INTERP_POWER);
  }
  foreach my $point (@w_ave_pts) {
    $dist = sqrt(($br_lat - @{@shake_pts[$point]}[1])**2 + ($br_lon - @{@shake_pts[$point]}[2])**2);
    $wa_psa03 = $wa_psa03 + ((($dist**$INTERP_POWER)/$wav_denom) * @{@shake_pts[$point]}[5]);             #acumulate a weighted average for psa03
    $wa_pga = $wa_pga + ((($dist**$INTERP_POWER)/$wav_denom) * @{@shake_pts[$point]}[2]);
    $wa_psa10 = $wa_psa10 + ((($dist**$INTERP_POWER)/$wav_denom) * @{@shake_pts[$point]}[6]);
  }
RSTATEMENT:
  return($wa_psa03, $wa_psa10, $wa_pga, @{@shake_pts[@boundpts[1]]}[1], @{@shake_pts[@boundpts[1]]}[0]);  #return the weighted average psa03 and the last boundry point (legacy)
}



sub find_grids {
my $bridge = shift(@_);
my $nw_pt = -1;
my $sw_pt = -1;
my $ne_pt = -1;
my $se_pt = -1;
my $beg = 0;
my $end = (scalar(@shake_pts) - 1);
($beg, $end) = lat_search($beg, $end, $bridge);

#Test code -- JJL 8-16-2004 For testing output of lat_search
#my $beg_lat = @{@shake_pts[$beg]}[1];
#my $end_lat = @{@shake_pts[$end]}[1];
#$| = 1;        #unbuffers the output for testing purposes
#print "\n LATSEARCH OUTPUT Beg: ", $beg, " ", $beg_lat, " Latsearch end: ", $end, " ", $end_lat;
#print "\n bridge lat/lon: ", @{$bridge}[1], " ", @{$bridge}[2];
#End test code -- (copied from the first segment in lat_search itself, then modified)

if (@{@shake_pts[$beg]}[1] == @{@shake_pts[$end]}[1]) {                      #the latitude of the bridge exactly matched a grid and so there are only 2 other points.
  ($sw_pt, $se_pt) = lon_search($beg, $end, $bridge);
}
else {
  ($nw_pt, $ne_pt) = lon_search($beg, int($beg + (($end - $beg)/2)), $bridge); #divide the ones selected from lat_search() in half -- relies on same num of grids/row
  ($sw_pt, $se_pt) = lon_search(int($beg + (($end - $beg)/2)), $end, $bridge); 
  }

#The if statement below occurs when lon_search returns at least one point that signals
#that the bridge data was bad.  Make sure this signal gets propagated.

#Test code -- dumps the selected grid point values JJL 8-16-2004
#print "\n SW: ", @{@shake_pts[$sw_pt]}[1], "," ,@{@shake_pts[$sw_pt]}[0], " NW: ", @{@shake_pts[$nw_pt]}[1], "," ,@{@shake_pts[$nw_pt]}[0],  " SE: ", @{@shake_pts[$se_pt]}[1], "," ,@{@shake_pts[$se_pt]}[0],  " NE: ", @{@shake_pts[$ne_pt]}[1], "," ,@{@shake_pts[$ne_pt]}[0];

#print "\n bridge lat/lon: ", @{$bridge}[1], " ", @{$bridge}[2];
#End test code.

if (($nw_pt == -100) || ($sw_pt == -100) || ($ne_pt == -100) || ($se_pt == -100)) {
  return(-100,-100,-100,-100);
}


return($sw_pt, $nw_pt, $se_pt, $ne_pt);
}


sub lat_search {
(my $beg, my $end, my $bridge) = @_;
my $center = 0;
my $grid_max = $#shake_pts;

#*********** TEST CODE -- dumps the status and important variables of this function each call.  For debugging this function and the search algorithm.
#my $beg_lat = @{@shake_pts[$beg]}[1];
#my $end_lat = @{@shake_pts[$end]}[1];
#$| = 1;        #unbuffers the output for testing purposes
#print "\n latsearch Beg: ", $beg, " ", $beg_lat, " Latsearch end: ", $end, " ", $end_lat;
#print "\n bridge lat/lon: ", @{$bridge}[1], " ", @{$bridge}[2];
#print "\n grid_max : ",$grid_max;
#********** END TEST CODE

my $new_beg = $beg;
my $new_end = $end;

if (($end - $beg) <= 1) {
  my $ref = $beg;
  if (@{$bridge}[1] < @{@shake_pts[$ref]}[1]) {                              #We've picked a point with a lat slightly over that of the bridge
    while(@{@shake_pts[$new_end]}[1] == @{@shake_pts[$ref]}[1]) {            #These 2 whiles put the end point at the last gridline of the latitude just below the bridge
      if ($new_end == $grid_max) {last;} 
      $new_end = $new_end + 1;
    }
    if ($new_end < $grid_max) {

#***********  TEST CODE -- For testing this function and algorithm in a different place in the loop.
#$beg_lat = @{@shake_pts[$new_beg]}[1];
#my $extra_lat = @{@shake_pts[($new_end + 1)]}[1];
#$end_lat = @{@shake_pts[$new_end]}[1];
#$grid_max = $#shake_pts;
#$| = 1;
#print "\n midloop latsearch new_Beg: ", $beg, " ", $beg_lat, " Latsearch new_end: ", $end, " ", $end_lat, " extra: ", $extra_lat;
#print "\n midloop bridge lat/lon: ", @{$bridge}[1], " ", @{$bridge}[2];
#print "\n midloop grid_max : ",$grid_max;
#**********  END TEST CODE

      while((@{@shake_pts[$new_end + 1]}[1]) == (@{@shake_pts[$new_end]}[1])) {
	$new_end = $new_end + 1;
	if ($new_end == $grid_max) {last;}
      }
    }
    while(@{@shake_pts[$new_beg]}[1] == @{@shake_pts[$ref]}[1]) {            #This while puts the beginning point at the first gridline of the latitude just above the bridge
      $new_beg = $new_beg - 1;
      if ($new_beg == 0) {last;}
    }
    return($new_beg, $new_end);
  }
  if (@{$bridge}[1] > @{@shake_pts[$ref]}[1]) {                              #We've picked a point with a lat slightly under that of the bridge
    while(@{@shake_pts[$new_beg]}[1] == @{@shake_pts[$ref]}[1]) {            #These 2 whiles put the end point at the first gridline of the latitude just over the bridge
      $new_beg = $new_beg - 1;
      if ($new_beg == 0) {last;}
    }
    if ($new_beg > 0) {
      while(@{@shake_pts[($new_beg - 1)]}[1] == @{@shake_pts[$new_beg]}[1]) {
	$new_beg = $new_beg - 1;
	if ($new_beg == 0) {last;}
      }
    }
    while(@{@shake_pts[$new_end]}[1] == @{@shake_pts[$ref]}[1]) {            #This while puts the end point at the last gridline of the latitude just above the bridge
      $new_end = $new_end + 1;
      if ($new_end == $grid_max) {last;}
    }
    return($new_beg, $new_end);
  }
  if (@{$bridge}[1] == @{@shake_pts[$ref]}[1]) {                              #We've picked a grid point that has a latitude equal to that of the bridge 
    if ($new_beg > 0) {
      while(@{@shake_pts[($new_beg - 1)]}[1] == @{@shake_pts[$new_beg]}[1]) {
	$new_beg = $new_beg - 1;
	if ($new_beg == 0) {last;}
      }
    }
    if ($new_end < $grid_max) {
      while(@{@shake_pts[($new_end + 1)]}[1] == @{@shake_pts[$new_end]}[1]) {
	$new_end = $new_end + 1;
	if ($new_end == $grid_max) {last;}
      }
    }
    return($new_beg, $new_end);
  }
}
                                                                              #if we haven't narrowed the proximity down to two or less grid points yet, recurse.

$center = int($beg + ($end - $beg)/2);

#********* NOTE
#Instead of enforcing rounding, lets just abort the recursion in the case of what would otherwise be an infinite loop consuming all RAM
#This policy makes sure that the grid set keeps converging with successive calls.  Rounding could cause convergence to cease otherwise.
#*********

if (@{$bridge}[1] > @{@shake_pts[$center]}[1]) {
  ($new_beg, $new_end) = lat_search($beg, $center, $bridge);
  return($new_beg, $new_end);
}
elsif (@{$bridge}[1] < @{@shake_pts[$center]}[1]) {
  ($new_beg, $new_end) = lat_search($center, $end, $bridge);
  return($new_beg, $new_end);
}
elsif (@{$bridge}[1] == @{@shake_pts[$center]}[1]) {
  ($new_beg, $new_end) = lat_search($center, $center, $bridge);
  return($new_beg, $new_end);
}
}


sub lon_search {
(my $beg, my $end, my $bridge) = @_;
my $center = 0;
my $grid_max = $#shake_pts;

if($beg == -100) {    #These take care of bridges dropped by a call of lon_search.
  return(-100,-100);
}
if($end == -100) {
  return(-100,-100);
}

#**********   Test Code -- for debugging the grid finding functions. Outputs grid indices every call.
#$| = 1;
#print "\n lonsearch Beg: ", $beg, " ",@{@shake_pts[$beg]}[0] , " ", @{@shake_pts[$beg]}[1], "\n";
#print "\n Lonsearch end: ", $end, " ",@{@shake_pts[$end]}[0] , " ", @{@shake_pts[$end]}[1], "\n";
#print "\n bridge lat/lon: ", @{$bridge}[1], " ", @{$bridge}[2];
#**********   End test code

if (($end - $beg) <= 1) {
  if (($beg < $grid_max) && ($beg > 0)) {            #Have to make sure we don't overshoot the array index. (index checking prevents run-time errors.)
    if ((@{$bridge}[2] > @{@shake_pts[$beg]}[0]) && (@{$bridge}[2] < @{@shake_pts[($beg + 1)]}[0])) {    #we've isolated the gridpoint right before that borders the bridge on the lesser longitude side
      return($beg, ($beg + 1));
    }
    elsif ((@{$bridge}[2] < @{@shake_pts[$beg]}[0]) && (@{$bridge}[2] > @{@shake_pts[($beg - 1)]}[0])) {   #we've got the one right after the bridge 
      return(($beg - 1), $beg);
    }
    elsif (@{$bridge}[2] == @{@shake_pts[$beg]}[0]) {
      return($beg, $beg);
    }
    elsif (@{$bridge}[2] == @{@shake_pts[$end]}[0]) {
      return($end, $end);
    }
    else {
      $! = 1;
      print "\nWarning: lon_search was confused at possible confusion point 1 by a bridge at: ", @{$bridge}[1], ",", @{$bridge}[2], "\n Bridge ignored.\n";
      return(-100,-100);    #This signals the calling functions to drop the bridge.
    }
  }
  else {          #Our beginning index is at one of the extremes.
    if ($beg == $grid_max) {
      if (@{$bridge}[2] > @{@shake_pts[$beg]}[0]) {    #we've isolated the gridpoint right before that borders the bridge on the lesser longitude side
	print "\nWarning: Trying to overshoot the grid array in Lon_search. Bridge at ", @{$bridge}[1]
	, ",", @{$bridge}[2], " ignored.\n";
	return(-100,-100);
      }
      elsif ((@{$bridge}[2] < @{@shake_pts[$beg]}[0]) && (@{$bridge}[2] > @{@shake_pts[($beg - 1)]}[0])) {   #we've got the one right after the bridge 
	return(($beg - 1), $beg);
      }
    }
    if ($beg == 1) {
      if (@{$bridge}[2] < @{@shake_pts[$beg]}[0]) {    #we've isolated the gridpoint right after that borders the bridge on the greater longitude side
        print "\nWarning: Trying to undershoot the grid array in Lon_search. Bridge at ", @{$bridge}[1]
              , ",", @{$bridge}[2], " ignored.\n";
	return(-100,-100);
      }
      elsif ((@{$bridge}[2] > @{@shake_pts[$beg]}[0]) && (@{$bridge}[2] < @{@shake_pts[($beg + 1)]}[0])) {   #we've got the one right before the bridge 
	return($beg, ($beg + 1));
      }
    }
    elsif (@{$bridge}[2] == @{@shake_pts[$beg]}[0]) {
      return($beg, $beg);
    }
    elsif (@{$bridge}[2] == @{@shake_pts[$end]}[0]) {
      return($end, $end);
    }
    else {
      $! = 1;
      print "\nWarning: lon_search was confused at possible confusion point 2 by a bridge at: ", @{$bridge}[1], ",", @{$bridge}[2], "\n Bridge ignored.\n";
      return(-100,-100);     #This signals the calling function to drop the bridge.
    }

  }
    
}
$center = int($beg + ($end - $beg)/2);

#********* NOTE
#Instead of enforcing rounding, lets just abort the recursion in the case of what would otherwise be an infinite loop consuming all RAM
#This policy makes sure that the grid set keeps converging with successive calls.  Rounding could cause convergence to cease otherwise.
#*********

if (@{$bridge}[2] < @{@shake_pts[$center]}[0]) {
  return(lon_search($beg, $center, $bridge));
}
elsif (@{$bridge}[2] > @{@shake_pts[$center]}[0]) {
  return(lon_search($center, $end, $bridge));
}
elsif (@{$bridge}[2] == @{@shake_pts[$center]}[0]) {
  return(lon_search($center, $center, $bridge));
}

}

sub usage {
  print "\nUsage : <(inventory file) (gridfile)> or <-event (eventID)>\n";
}

sub parse_gridfile {
  #
  #set the newline character to 0x0a for this file -- it's what Shakemap produces for some strange reason.
  #then do things just like for the inventory file for the moment -- same sort of array of references to arrays business.
  #keep in mind that the first row of the 2D array contains the meta info for the grid file.  It probably has only one column.
  #
   my $tmp_sep = $/;
   $/ = qq{\x0a};                          #grid files have 0x0a as the line terminator.
   @map_params = split(" ", <GRID_HDL>);   #Splits the grid file metaline up into values.
   $west_bdry = $map_params[9] + $LON_BUF;            #sets the boundry variables from the meta line. (These are global variables.)
   $south_bdry = $map_params[10] + $LAT_BUF;
   $east_bdry = $map_params[11] - $LON_BUF;
   $north_bdry = $map_params[12] - $LON_BUF;
   while(<GRID_HDL>) {                       #reads in the grid file, throws out all the lines that don't have 8 objects.
       $grids_in = $grids_in + 1;
       my @gridline = split(" ", $_);
     #    print "\n Just read: ", join(":",@gridline);
       if (scalar(@gridline) == 8 && $gridline[5] > 0.0 && $gridline[6] > 0.0) {
	   $grids_used = $grids_used + 1;
	   push(@shake_pts, \@gridline);
       }
       $/ = $tmp_sep;
   }
}

sub parse_inventory {
  #
  #  Read in the bridge inventory.
  #    We'll use an array of references to the arrays that actually hold the data.
  #    Keep an index so that we can assign a number to each bridge for ease in correlation.  This index starts at 0.
  #  Documentation update: This index isn't really used in this program, but it is there should someone want to use it.  
  #  The index is essentially just a bridge number that is assigned when the file is read in.  They are sequential.
  #

  my $index = 0;
  
  while(<INV_HDL>) {
    $in_count = $in_count + 1;
    # Read a line and chop it up by colons. Insert the index in front.
    
    my @bridge = ($index,split(":"));

    #TEST CODE -- dumps the index and number of elements of the bridge reference array, there should be a consistent pattern here.
    #print "\n",$index, " ",scalar(@bridge);
    #END TEST CODE
    
    #
    #push the reference to the array onto the array of references
    #but only if the bridge line has the right number of elements.
    #

    if (scalar(@bridge) == 12) {
      push(@bridges, \@bridge);
      $index = $index + 1;
    }                               #If the data is incomplete, keep a record in the bridge array, but do not process it, set values to 0.
    else {
      @bridge = ($index,0,0,0,0,0,0,0,0,0,0,0,0);
      push(@bridges, \@bridge);
    }
    
  }
}



sub UW_prob_calc {                                                   
(my $br_year, my $br_span, my $br_psa03) = @_;                       
my $Pd = 0;
    if ($br_year <= @uw_years[0]) {
      if (($br_span >= 15) && ($br_span <= 17)) {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam4)/$xi4);   #pnorm assumes a mean of 0 and a sigma of 1.  This function isn't documented 
	goto(PROBCALCDONE);
      }                                                      #in the standard perl docs.  It's only documented within the module comments.
      elsif (($br_span >= 9) && ($br_span <= 10)) {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam5)/$xi5);
	goto(PROBCALCDONE);
      }
      else {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam1)/$xi1);
	goto(PROBCALCDONE);
      }
    }
    elsif ($br_year <= @uw_years[1]) {
      if (($br_span >= 15) && ($br_span <= 17)) {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam4)/$xi4);   #pnorm assumes a mean of 0 and a sigma of 1.  This function isn't documented 
	goto(PROBCALCDONE);
      }                                                      #in the standard perl docs.  It's only documented within the module comments.
      elsif (($br_span >= 9) && ($br_span <= 10)) {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam5)/$xi5);
	goto(PROBCALCDONE);
      }
      else {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam2)/$xi2);
	goto(PROBCALCDONE);
      }
    }
    else {
      if (($br_span >= 15) && ($br_span <= 17)) {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam4)/$xi4);   #pnorm assumes a mean of 0 and a sigma of 1.  This function isn't documented 
	goto(PROBCALCDONE);
      }                                                      #in the standard perl docs.  It's only documented within the module comments.
      else {
	$Pd = Math::CDF::pnorm(log($br_psa03/$lam3)/$xi3);
	goto(PROBCALCDONE);
      }
    }
  PROBCALCDONE:
    return($Pd);         #returns the UW damage probability.
}




sub HAZUS_prob_calc {                                                                           #this does classification and damage calculation probability 
  my $br_length = 0;
  my $HPd = 0;
  my $mean = 0;
  my $br_htype = 0;
  (my $br_ref, my $br_psa03, my $br_psa10, my $br_pga) = @_;     #insert these variables here
  my $br_year = @{$br_ref}[3];  #These are here mostly to make parts of the code more clear.  See the table at the top for more information about what all these arrays are.
  my $br_span = @{$br_ref}[5];  #note -- span here is the span type, not the length of the bridge.  Not all of these are used here.  Their scope is local.
  my $br_len = @{$br_ref}[9];
  my $br_nbilen = @{$br_ref}[10];
  my $br_maxspan = @{$br_ref}[11];
  my $br_matl = @{$br_ref}[7];
  my $br_des = @{$br_ref}[5];
  if ($br_nbilen > 0) {
      $br_length = $br_nbilen;                                                                        #select length from the two, set $br_length
    }
    else {
      $br_length = $br_len;
    }
  $br_htype = HAZUS_classify($br_ref, $br_length);            #Performs the HAZUS classification
  @{$br_ref}[14] = $br_htype;                                 #Records the HAZUS type in the array.

  #
  #***** This is the part where it actually does the probability calculation.  I've elected not to make an array or otherwise reorganize the mean values
  # because some of them are actually calculated in this part itself and are therefore not really constant in the global context.
  # 

  if ($br_htype == 1) {
    $mean = 0.4;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 2) {
    $mean = 0.6;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 5) {
    $mean = 0.25;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 7) {
    $mean = 0.5;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 10) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.6;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 11) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.9;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 12) {                                    #yes, I realize that this is the same as $h_type == 5. I kept it this way to make things more clear. 
    $mean = 0.25;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 14) {
    $mean = 0.5;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 15) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.75;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 16) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.9;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 17) {
    $mean = 0.25;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 19) {
    $mean = 0.5;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 22) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.6;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 23) {
    $mean = 2.5*($br_psa10/$br_psa03);
    if (1 < $mean) {
      $mean = 1;
    }
    $mean = $mean * 0.9;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 24) {
    $mean = 0.25;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 26) {
    $mean = 0.75;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
  elsif ($br_htype == 28) {
    $mean = 0.8;
    $HPd = Math::CDF::pnorm(log(($br_psa10/100)/$mean)/$HAZUS_SD);
  }
return($HPd);
}

#******
#  End of HAZUS_prob_calc
#******


sub HAZUS_classify {     
  (my $br_ref, my $br_length) = @_;
  my $br_year = @{$br_ref}[3];
  my $br_matl = @{$br_ref}[7];
  my $br_des = @{$br_ref}[5];
  my $br_maxspan = @{$br_ref}[11];
  if ($br_maxspan >= 492.13) {
    if ($br_year <= $HAZUS_YEAR) {
      return(1);
    }
    else {
      return(2);
    }
  }
  elsif ($br_matl == 1) {
    if (($br_des >= 1) && ($br_des <= 6)) {
      if ($br_year <= $HAZUS_YEAR) {
	return(5);
      }
      else {
	return(7);
      }
    }
    else {
      return(28);
    }
  }
  elsif ($br_matl == 2) {
    if (($br_des >= 1) && ($br_des <=6)) {
      if ($br_year <= $HAZUS_YEAR) {
	return(10);
      }
      else {
	return(11);
      }
    }
    else {
      return(28);
    }
  }
  elsif ($br_matl == 3) {
    if (($br_des >= 1) && ($br_des <= 6)) {
      if ($br_year <= $HAZUS_YEAR) {
	if ($br_length <= 65.62) {
	  return(24);
	}
	else {
	  return(12);
	}
      }
      else {
	return(14);
      }
    }
    else {
      return(28);
    }
  }
  elsif ($br_matl == 4) {
    if (($br_des >= 2) && ($br_des <= 10)) {
      if ($br_year <= $HAZUS_YEAR) {
	if ($br_length <= 65.62) {
	  return(26);
	}
	else {
	  return(15);
	}
      }
      else {
	return(16);
      }
    }
    else {
      return(28);
    }
  }
  elsif ($br_matl == 5) {
    if (($br_des >= 1) && ($br_des <= 6)) {
      if ($br_year <= $HAZUS_YEAR) {
	return(17);
      }
      else {
	return(19);
      }
    }
    else {
      return(28);
    }
  }
  elsif ($br_matl == 6) {
    if (($br_des >= 1) && ($br_des <= 7)) {
      if ($br_year <= $HAZUS_YEAR) {
	return(22);
      }
      else {
	return(23);
      }
    }
    else {
      return(28);
    }
  }
  else {
    return(28);
  }
}


    
