#!/bin/bash

container_name=$1
trace_file="$container_name.trace"  # helloworld.trace
org_rootfs="${container_name}_org"
hot_rootfs="${container_name}_hot"

workdir=$HOME/$container_name
mkdir $workdir
pushd $workdir

python3=false

touch hots

echo "$org_rootfs.tar.gz"
if [[ -f $workdir/$org_rootfs.tar.gz ]] ; then
	echo "container rootfs exists"
else
	while true; do
    read -p "Will exporting container $container_name's rootfs, Do you have a running container $container_name? " yn
    case $yn in
        [Nn]* ) exit;;
        [Yy]* ) 
		echo "Exporting container $container_name's rootfs..."
		docker container export $container_name -o $org_rootfs.tar.gz
		mkdir $org_rootfs && tar -xvf $org_rootfs.tar.gz -C $org_rootfs
		echo "Export sucessfully"
		break;;
        * ) echo "Please answer yes or no.";;
    esac
	done
fi



echo "Searching hot files..."
pushd $org_rootfs
# filter files opened by open() syscall
#  grep -v "\.pyc"
if [[ python3 == true ]]; then
	grep 'opena\?t\? fd='  $HOME/$trace_file |awk '{if ($4 !~ /fd=-/) print $0}'|awk -F 'name=/' '{print $2}'|awk '{print $1}'|grep -v ^dev/ | grep -v ^sys/ | grep -v ^proc/|sort | uniq >> $workdir/hots
else
	grep 'opena\?t\? fd='  $HOME/$trace_file |awk '{if ($4 !~ /fd=-/) print $0}'|awk -F 'name=/' '{print $2}'|awk '{print $1}'|grep -v ^dev/ | grep -v ^sys/ | grep -v ^proc/| grep -v "\.pyc" | sort | uniq >> $workdir/hots
fi
grep -e "stat\sfd"  $HOME/$trace_file | grep -v ENOENT | awk '{print $4}' | cut -d ">" -f2 | cut -d ")" -f1 | cut -c 2-  | grep -v ^dev/ | grep -v ^sys/ | grep -v ^proc/ | sort | uniq >> $workdir/hots
grep '\sstat res=0' $HOME/$trace_file | cut -d" " -f5 | awk -F 'path=/' '{print $2}' | sort | uniq >> $workdir/hots
# add files opened by execve() syscall
grep execve.filename $HOME/$trace_file |awk -F 'filename=/' '{print $2}' | sort | uniq >> $workdir/hots

# add shell binary and linker

find . -name "ld-linux*" >> $workdir/hots
echo "usr/bin/bash usr/bin/sh bin/sh bin/bash"  >> $workdir/hots # need fix 

hots=$(sort $workdir/hots | uniq)
# mkdir $workdir/$hot_rootfs
# for hot in $hots; do
# 	if [[ -d $hot ]]; then
# 		echo $hot >> ../hotdirse
# 	else
# 		echo $hot >> ../hotfiles
# 	fi
# done 


# for i in ${hot_dir[@]}; do
# 	hot_files=("${hot_files[@]/$i}")
# done

# echo "Found hot files: $hot_file"

# echo $hot_files > hot

echo "Extracting hot files from original rootfs..."
hot_files=$(sort $workdir/hots | uniq)

echo $hot_files | xargs tar cvz -f ../$hot_rootfs.tar.gz -P

popd

mkdir $hot_rootfs 
tar -xvf $hot_rootfs.tar.gz -C $hot_rootfs -P && cd $hot_rootfs

echo "Handling soft link..."
links=$(find . -type l)
echo $links
for l in $links; do
	target=$(ls -hl $l |awk -F '-> ' '{print $2}'|grep -v '^$')
	if [[ $target != /* ]]; then
		link_dir=$(dirname $l)
		cp ../$org_rootfs/$link_dir/$target ../$hot_rootfs/$link_dir/$target
	fi
done

# handle pycache
if [[ python3 == true ]]; then
	echo "Handling python cached bytecode..."
	pycache_dirs=$(find . -name "*pycache*")
	for dir in $pycache_dirs; do
		rename 's/cpython-38\.//' $dir/*
		parentdir="$(dirname "$dir")"
		mv $dir/* $parentdir/
		rm -r $dir
	done
fi

echo "Done, please find the hot files in $hot_rootfs"
