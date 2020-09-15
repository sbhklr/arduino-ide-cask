#!/bin/bash

#############################################
# Description: Brew Cask Deployment Script  #
# Author: Sebastian Romero                  #
# Date: 13.9.2020                           #
#############################################

cask_name="arduino-ide-2"
app_name="Arduino Pro IDE"
host_path="https://downloads.arduino.cc/arduino-pro-ide"


# Parameter validation
helpFunction()
{
   echo ""
   echo "Usage: $0 <DMG path or URL> <flags>"   
   echo -e "\t-i --install \t Install the app locally"
   echo -e "\t-l --launch \t Launch app after installation"
   echo -e "\t-t --test \t Test the cask"
   echo -e "\t-p --publish \t Publish the cask by pushing it to Github"   
   echo -e "\t-h --help \t Print this help message"
   exit 1 # Exit script after printing help
}

if [ -z "$1" ]; then
  helpFunction
fi

installation_file=$1
shift

for arg in "$@"
do
    case $arg in        
        -i|--install)
        SHOULD_INSTALL=1
        shift
        ;;
        -l|--launch)
        SHOULD_LAUNCH=1
        shift
        ;;
        -t|--test)
        SHOULD_TEST=1
        shift
        ;;
        -p|--publish)
        SHOULD_PUBLISH=1
        shift
        ;;
        -h|--help)
        helpFunction
        shift
        ;;
        *)   
        echo "Unknown flag $arg"
        helpFunction      
        exit
        ;;
    esac
done


# Ensure app installation file is available

url_check_regex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'

if [[ $installation_file =~ $url_check_regex ]]
then
	echo "Downloading file $installation_file ..."
  curl -OJL $installation_file
  image_path=$(basename $installation_file)
  echo "Image ready at $image_path"
else
	echo "Using local file $installation_file"
  image_path=$installation_file
fi

if [ ! -f  $image_path ]
then
  echo "❌ Target image not found at $image_path"
  exit 2
fi


# Gathering data for cask file

echo "Mounting image $image_path ..."
hdiutil attach $image_path -quiet
image_name=$(basename $image_path)
volume=$(ls /Volumes | grep "^$app_name")
mount_point=$(hdiutil info | grep "$app_name"  | awk -F' ' '{print $1}')

app_path="/Volumes/${volume}/$app_name.app"
echo "🎯 App path: $app_path"

app_version=$(plutil -p "${app_path}/Contents/Info.plist" | grep CFBundleShortVersionString | awk -F'"' '{print $4}')
echo "📱 App version: $app_version"
hdiutil detach $mount_point -quiet

checksum=($(shasum -a 256 "$image_path"))
echo "👀 SHA 256 Checksum: $checksum"


# Nightly Build Config

if [[ "$app_version" == *"nightly"* ]]; then
  echo "📣 Creating a nightly build cask..."
  homebrew_repository="homebrew-cask-versions"
  cask_name="$cask_name-nightly"
  host_path="$host_path/nightly"
else  
  echo "📣 Creating a stable release cask..."
  homebrew_repository="homebrew-cask"
fi


# Generate Cask File

cask_file_name="$cask_name.rb"
printf "📦 Generating cask file $cask_file_name at $(pwd) ...\n\n"

cask_directory="$(brew --repository)/Library/Taps/homebrew/homebrew-cask/Casks"
cask_path="$cask_directory/$cask_file_name"

if ! curl --output /dev/null --silent --head -L --fail "$host_path/$image_name"; then
  echo "❌ Resource at $host_path/$image_name not available."
  exit 3
fi

if [ -f  $cask_file_name ]
then
	rm $cask_file_name
fi
cat <<EOF > $cask_file_name
cask "$cask_name" do
  version "$app_version"
  sha256 "$checksum"

  # downloads.arduino.cc was verified as official when first introduced to the cask
  url "$host_path/$image_name"
  name "$app_name"
  desc "The $app_name is a modern Development Environment for Arduino Programming"
  homepage "https://github.com/arduino/arduino-pro-ide"

  app "$app_name.app"
end
EOF

cat $cask_file_name
printf "\n"

if [ ! -d  $cask_directory ]
then
  echo "❌ No cask directory found at $cask_directory"
  exit 4
fi

if [ -f  $cask_path ]
then
	echo "👋 Removing old cask file at $cask_path"
	rm $cask_path
fi

echo "👉 Copying $cask_file_name to $cask_path"
cp "$cask_file_name" "$cask_path"


# Installation

if [[ $SHOULD_INSTALL == 1 ]] ;then	
  export HOMEBREW_NO_AUTO_UPDATE=1
	brew cask install $cask_name --force	
	unset HOMEBREW_NO_AUTO_UPDATE
fi


# Testing Cask

if [[ $SHOULD_TEST == 1 ]] ;then
	brew cask audit "$cask_name" --download
	brew cask style --fix "$cask_name"
fi


# Publishing the Cask

if [[ $SHOULD_PUBLISH == 1 ]] ;then
    echo "🚚 Publishing..."
    branch_name="release-$app_version"
    cd "$(brew --repository)"/Library/Taps/homebrew/homebrew-cask
    git status
    git checkout -b $branch_name
    git add Casks/$cask_file_name
    git commit -m "Add $app_name.app v$app_version"

    git remote add fork https://github.com/arduino/homebrew-cask.git
    git remote -v
    git push fork $branch_name
    git checkout master
    open "https://github.com/Homebrew/$homebrew_repository/compare/master...arduino:$branch_name"
fi


# Launch app

if [[ $SHOULD_LAUNCH == 1 ]] ;then
  open -a "$app_name"
fi


echo "✅ Cask '$cask_name' generated"