#!/bin/bash 

base_url="http://www.multigp.com/races/view"
dump="./race_file_raw"
authfile="./auth"
login_url="http://www.multigp.com/user/site/login"

cleanup()
{
	[ -f cjar ] && rm -f cjar
	[ -f convert.php ] && rm -f convert.php
	#[ -f $dump ] && rm -f $dump
	[ -f race.html ] && rm -f race.html
}

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
	cleanup
	exit "$st"
}

write_csv_headers()
{
	echo "MultiGP Race $race,$url" > $csv
	echo "Name,Freq,Round 1,Round 2,Round 3,Round 4,Round 5,Round 6,Round 7,Round 8,Round 9,Final Points" >> $csv
}

write_csv_footer()
{
	echo "Misc" >> $csv
	echo "A,,,,,,,,,,," >> $csv
	echo "B,,,,,,,,,,," >> $csv
	echo "C,,,,,,,,,,," >> $csv
	echo "D,,,,,,,,,,," >> $csv
	echo "E,,,,,,,,,,," >> $csv
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

freq_regex="[0-9]{4}\ [A-Z]\ [0-9]"
pilot_regex="[0-9]+..[A-Z].[0-9]{4}\ (.*)"

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

do_public_mode()
{
	w3m -dump "$url" > $dump
	write_csv_headers

	# main parsing loop
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
	write_csv_footer
}

heat=''

do_login_mode()
{
	# read the auth file to get user/pass
	user=$(grep -E "^user:" $authfile | cut -d: -f2-)
	pass=$(grep -E "^pass:" $authfile | cut -d: -f2-)

	# login to mgp, and get the auth cookie
	curl -s --cookie-jar cjar --output /dev/null $login_url
	curl -s --cookie cjar --cookie-jar cjar \
		--data "LoginForm[username]=$user" \
		--data "LoginForm[password]=$pass" \
		--data 'yt0=Log in' \
		--location \
		--output $dump $login_url

	# download the race dump
	curl -s --cookie cjar --cookie-jar cjar --output race.html --location $url
	w3m -dump ./race.html > $dump
	[ -s $dump ] || die "error reading the race page"

	write_csv_headers
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		[[ "$line" == "Round #1" ]] && parse=1 && continue # start parsing
		[[ "$line" == "Round #2" ]] && parse='' # stop when reached
		[[ "$line" == "Pilots Racing" ]] && parse='' # stop when reached
		[ -n "$parse" ] || continue
		[[ "$line" == *"All Races"* ]] && continue
		echo $line

		if [[ "$line" =~ 1..Heat.([0-9]+) ]]; then
			heat="${BASH_REMATCH[1]}"
			echo " === H E A T  $heat ===" >> $csv
		fi
		if [ -n "$heat" ]; then
			if [[ $line =~ $pilot_regex ]]; then
				pilot="${BASH_REMATCH[1]}"
				pilot=$(cut -d' ' -f1 <<< $pilot)
				[[ "$pilot" == "[EMPTY]" ]] && pilot=''
			fi
			if [[ $line =~ $freq_regex ]]; then
				freq="$line"
				echo "$pilot,$freq,,,,,,,,,," >> $csv
			fi
		fi
	done < $dump
	write_csv_footer
}

## main ##

[ -s "$authfile" ] && do_login_mode || do_public_mode

[ -s $csv ] || die "error producing the CSV file"

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
cleanup
