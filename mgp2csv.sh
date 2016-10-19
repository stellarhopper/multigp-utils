#!/bin/bash 

base_url="http://www.multigp.com/races/view"
dump="./race_file_raw"

warn()
{
	printf '%s\n' "$@" >&2
}

die()
{
	local st=$?
		case $2 in
		*[^0-9]*|'') :;;
	*) st=$2;;
	esac
	warn "$1"
	exit "$st"
}

write_csv_headers()
{
	echo "MultiGP Race $race,$url" > $csv
	echo "Name,Freq,Round 1,Round 2,Round 3,Round 4,Round 5,Round 6,Round 7,Round 8,Round 9,Final Points" >> $csv
}

[ -n "$1" ] || die "Please provide a race number or URL"

url_race_regex="$base_url/([0-9]+)/.*"
case "$1" in
*[^0-9]*|'')
	url="$1"
	if [[ $url =~ $url_race_regex ]]; then
		race=${BASH_REMATCH[1]}
	else
		die "URL appears to be invalid"
	fi
	;;
*)
	race="$1"
	url="$base_url/$race"
	;;
esac
csv="./$race.csv"

w3m -dump "$url" > $dump
write_csv_headers

freq_regex="[0-9]{4}\ [A-Z]\ [0-9]"
parse=''
capture_freq=''
buf=''
started=0
skip=0
end=''

do_end()
{
	# write out
	echo "$buf" >> $csv
	end=''
	started=0
	buf=''
}

while IFS= read -r line; do
	[ -z "$line" ] && continue
	[[ "$line" == "Pilots Racing" ]] && parse=1 && continue # start parsing
	[[ "$line" == "Comments" ]] && parse='' # stop when 'Comments' reached
	[[ "$line" == "Leaderboard"* ]] && continue
	[ -n "$parse" ] || continue
	echo $line

	if [ $skip -gt 0 ]; then
		((skip-=1))
		continue
	fi

	if [ $started -eq 0 ]; then
		buf="$line"
		((started+=1))
	else
		if [ -n "$capture_freq" ]; then
			freq=''
			if [[ $line =~ $freq_regex ]]; then
				freq="$line"
			elif [[ "$line" == "--" ]]; then
				buf="$buf,$freq,,,,,,,,,,"
				skip=1
				end=1
			elif [[ $line =~ ([0-9]+).Points ]]; then
				skip=1
				end=1
				buf="$buf,$freq,,,,,,,,,,${BASH_REMATCH[1]}"
			fi
			capture_freq=''
			[ -n "$end" ] && do_end && continue
			buf="$buf,$freq,,,,,,,,,"
		fi

		if [[ "$line" == "--" ]]; then
			buf="$buf,"
			skip=1
			do_end && continue
		elif [[ $line =~ ([0-9]+).Points ]]; then
			buf="$buf,${BASH_REMATCH[1]}"
			skip=1
			do_end && continue
		fi
		if [[ "$line" == *"GHz"* ]]; then
			capture_freq=1
			continue
		fi
		[[ "$line" == *"Federal"* ]] && continue
		[[ "$line" == *"Academy"* ]] && continue
		[[ "$line" == *"Administration"* ]] && continue
	fi
done < $dump

cat > convert.php <<EOF
<?php
echo "<html><head><style>";
echo "table { border-collapse: collapse; }";
echo "table, td, th { border: 1px solid black; padding: 10px; } </style></head>";
echo "<body><table border=1>\n\n";
\$f = fopen("$csv", "r");
while ((\$line = fgetcsv(\$f)) !== false) {
        echo "<tr>";
        foreach (\$line as \$cell) {
                echo "<td>" . htmlspecialchars(\$cell) . "</td>";
        }
        echo "</tr>\n";
}
fclose(\$f);
echo "\n</table></body></html>";
EOF

php -f convert.php > $race.html
rm convert.php
rm $dump
