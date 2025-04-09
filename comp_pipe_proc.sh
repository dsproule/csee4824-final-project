#!/bin/bash

echo_color() {
	# 0:black, 1:red, 2:green, 3:yellow, 4:blue, 5:magenta, 6:cyan, 7:white
	if [ -t 0 ]; then tput setaf $1; fi;
	echo -n "${@:2:$#}"
	if [ -t 0 ]; then tput sgr0; fi
}


wrong=0
tested=0
# hashmap
declare -A file_status

indiv_prog=($(ls programs/* | cut -d. -f1 | uniq))
for file in "${indiv_prog[@]}"; do
	target=$(basename "$file")
	echo "Making $target..."
	make $target.out

	# checks if file exists after compilation
	if [[ ! -e output/$target.out && ! -e output/$target.wb ]] || \
		[[ ! -e correct_out/$target.out && ! -e correct_out/$target.wb ]]; then
		echo "Skipping $target — incomplete files"
		continue
	fi


	((tested++))
	file_status["$target"]=false
	echo_color 3 -e "Comparing mem output...\n"
	
	# stores only the mem outputs to compare
	grep '^@@@ mem\[' output/$target.out > t1.txt
	grep '^@@@ mem\[' correct_out/$target.out > t2.txt

	if [[ ! -z $(diff t1.txt t2.txt) ]]; then
		((wrong++))
		echo_color 1 -e "Mistmatch between mem outputs in $target\n"
		continue
	fi
	
	# echo "Comparing wb output..."

	# if [[ ! -z $(diff output/$target.wb correct_out/$target.wb) ]]; then
	# 	((wrong++))
	# 	echo_color 1 -e "Mistmatch between wb outputs in $target\n"
	# 	continue
	# fi

	file_status["$target"]=true
	echo_color 2 -e "Success on $target\n"	
done

rm t1.txt
rm t2.txt

echo_color 7 -e "\n\n$(($tested - $wrong)) / $tested files passed!\n"
echo_color 7 -e "=============================================\n"

for key in "${!file_status[@]}"; do
	echo_color 7 "$key ("
	if [[ "${file_status[$key]}" == "true" ]]; then
		echo_color 2 "SUCCESS"
	else
		echo_color 1 "FAILED"
	fi
	echo_color 7 -e ")\n"
done

# cd ~/csee4824/proj3/
# ./check_timing.sh