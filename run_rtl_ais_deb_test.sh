#!/bin/bash
# This test script is for the rtl_ais program
# * assumes Debian based OS like Raspbian or Ubuntu 16.04 LTS
# * will install the kalibrate-rtl git repo clock PPM drift finder program
# * is notated for tests done on a specific E4000 rtl dongle with the documented antenna
#
# It is GPLv2 (c)2017 if relevant to the users  =)
#
# I do not provide any warranty of the item whatsoever, whether express, implied, or
# statutory, including, but not limited to, any warranty of merchantability or fitness
# for a particular purpose or any warranty that the contents of the item will be error-free. 
#
# j031mckay@gmail.com
#
#
#TO DO: Suggest brute-force step-and-check tuning (reuse ram buffer data)
# as peak detection will not work well alone. Thus, we must scan each band 
# tuning region with +- 0.002MHz for best SNR stats.
# If we maximize valid packet counts, than the off-peak-center packet data should be better.
#

currdir=$(pwd)
xtalFile=$currdir"/xtal_station_ref.txt"
xtalPPM=$currdir"/xtal_ppm.txt"

echo ""
echo "=D~~~~~~[:o:::]+===================+"
echo "We used an 88cm long 1/4\" threaded rod for a 1/2 wavelength 162MHz antenna,"
echo "and directly coupled into a copper-foil covered E4000 RTL SDR receiver"
echo "Note: this setup reached >10km with the PGA set to 24dB gain"
echo ""

#check if resources are available
kalprg=$currdir"/kalibrate-rtl/src/kal"
if [ ! -f  $kalprg ]
then
	echo "====================================================================="
	echo "Error: no kalibrate-rtl found at $kalprg"
	echo "====================================================================="
	echo "Building tool "
	echo "Install deb packages "

	sudo apt-get install libtool autoconf automake libfftw3-dev
	
	echo "Install src from repo if mssing..."
	git clone https://github.com/asdil12/kalibrate-rtl.git
	
	
	kalprgsrc=$currdir"/kalibrate-rtl"
	if [ ! -f  $kalprg ]
	then
		cd $kalprgsrc
		git checkout arm_memory
		echo "compile src "
		./bootstrap
		./configure
		make
		
		echo "Install kal program in system "
		sudo make install
	else
		echo "Error: could not build program"
	fi
	echo "====================================================================="
	echo "retry this script when ready..."
	exit 0 
fi


#check if rtl_ais available
rtlprg=$currdir"/rtl_ais"
if [ ! -f  $rtlprg ]
then
	echo "====================================================================="
	echo "Building rtl_ais "
	make
	
	if [ ! -f  $rtlprg ]
	then
		echo "====================================================================="
		echo "Eroor: unable to find ./rtl_ais ..."
		exit 0 
	fi
fi


#check if station list is older than 5 hours
isOldClockStat=$( find $xtalFile  -mmin +300 ) 
if [ ! "$isOldClockStat" = "" ]
then
	echo "Station list is older than 5 hours, re-calibrate clock"
	rm $xtalFile
else
	echo "Re-used recent station list"
fi

#Scan station listing, and get PPM error
initHzoffset="0"
if [ ! -f $xtalFile ] || [ ! -f $xtalPPM ]
then
	echo "Find strongest GSM850 cell tower to calibrate the PPM calculation"
	echo "This may take a few minutes..."
	$kalprg -s GSM850 -b GSM850 -g 42 -e $initHzoffset 2>&1 | grep 'chan:' | cat > $xtalFile
	#filter for strongest local signal source
	hzOffsetChan=$( cat $xtalFile | sed -r 's/[[:space:]]+/,/g'  | sort -k6,7 -n -t',' | grep -m1 'power' | cut -d',' -f3 | sed 's/[^0-9]//g' ) 
	
	if [ $hzOffsetChan = "" ]
	then
		#TO DO: add function to permute other common cell tower configs if GSM is missing
		echo "Error: unable to find local cell towers"
		exit 0
	else
		echo "Calibrate rtl XTAL PPM offset using GSM850 cell tower chan: $hzOffsetChan"
		echo "This may take a few minutes..."
		
		ppmOffset=$( $kalprg -c $hzOffsetChan -b GSM850 -g 42 -e $initHzoffset | grep 'absolute error' | cut -d' ' -f4  | sed 's/[^0-9\.\-]//g'  )
		echo "New Clock ppm drift Offset = $ppmOffset"
		echo "$ppmOffset" | cat > $xtalPPM
		sync
	fi
fi
 
if [ ! -f $xtalPPM ]
then
	echo "Error: unable to find PPM xtal offset"
	exit 0
fi

ppmOffset=$( cat  $xtalPPM | sed 's/[^0-9\.\-]//g' )
if [ $ppmOffset = "" ]
then
	echo "Error: unable to load PPM xtal offset"
	exit 0
fi

echo "Using Clock ppm drift Offset = $ppmOffset"
 
 
#############################################################
#These tests were run with Tuner error set to 18 ppm.

#RF peak is at 161.975M. 
#  has a kew to HF 6dB (noted band area as 6 in photo) 
#  seems to prefer uniform packet region (noted band area as 4 in photo)

#RF peak is at 162.025M
#  seems to prefer uniform packet region (noted band area as 2 in photo)


#advice:
#1. These values should be auto permuted +- 0.002MHz to maximize valid packet counts 
#2. Increase gain if no signal detected, and reduce  PGA to 24dB if high invalid packet length count
#
#note: CRC errors will fluctuate for 10% to 30% depending on time of day.
aisAHZ="161.97481M"
aisBHZ="162.02518M"   

#Real world Stats:
#Level on ch 0: 49 %
#Level on ch 1: 47 %
#A: Received correctly: 218 packets, wrong CRC: 42 packets, wrong size: 31 packets
#B: Received correctly: 224 packets, wrong CRC: 16 packets, wrong size: 35 packets


#############################################################
#These tests were run with Tuner error set to 17 ppm.

#------------------------------- AGC is not very effective with SNR
#ships tracked 3  (3km)
#$rtlprg  -R on -l $aisAHZ -r $aisBHZ  -s 24k -o 48k -p $ppmOffset  -n -S5
#------------------------------- 

#RTL E4000 lower gain amp seems to get better SNR fo rmore valid packets
#-------------------------------
#ships tracked 5 (10km) BEST data/range 
$rtlprg  -g 34 -l $aisAHZ -r $aisBHZ  -s 24k -o 48k -p $ppmOffset  -n -S10
#-------------------------------
# ships tracked 5  (10km) Does find weaker signals, but gets more packet errors with bad SNR
#$rtlprg  -g 42 -l $aisAHZ -r $aisBHZ  -s 24k -o 48k -p $ppmOffset  -n -S5
#-------------------------------
#ships tracked 4 (3km) range is low, but SNR is very good
#$rtlprg  -g 24 -l $aisAHZ -r $aisBHZ  -s 24k -o 48k -p $ppmOffset  -n -S5
#-------------------------------

 
 
		