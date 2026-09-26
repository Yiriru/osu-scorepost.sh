#!/bin/bash

# Config
clientID=""
clientSecret=""
userid=""
dansercli="$HOME/danser-go/danser-go"
replaydir="$HOME/danser-go/replays"
beatmapdir="$HOME/danser-go/songs"
videodir="$HOME/danser-go/videos"

openDir() {
	thunar "$1"
}

downloadBeatmap() {
	if ! [ -e "$beatmapdir/$1" ]
	then
		mkdir -p "$beatmapdir/$1/"
		wget "https://api.nerinyan.moe/d/$1" -O "$beatmapdir/$1/$1.zip"
		unzip "$beatmapdir/$1/$1.zip" -d "$beatmapdir/$1/"
		rm "$beatmapdir/$1/$1.zip"
	fi
}

log() {
	printf -- "\001\e[100m\002 \001\e[0m\002 $*\n"
}

error() {
	printf -- "\001\e[41m\002 \001\e[0m\e[31m\e[01m\002 $*\001\e[0m\002\n" 1>&2
	return 1
}

success() {
	printf -- "\001\e[42m\002 \001\e[0m\e[32m\e[01m\002 $*\001\e[0m\002\n"
}

testOpts() {
	IFS=';' read -ra argsList11 <<< "$1"
	shift 1

	while [ "$1" ]
	do
		case "$1" in
		"${argsList11[0]}"|"${argsList11[1]}")

			printf -- "%s" "$2"
			return 0
			;;
		esac
		shift
	done
	return 1
}

printf "v260925\n"
help() {
	if testOpts "-h;--help" $@ > /dev/null
	then
	cat <<EOF
Usage: $0 mode arguments [OPTIONS]

Modes available:
  score recent top replay clear

Score mode arguments:
  scoreid

Recent mode arguments:
  (Optional) userid

Top mode arguments:
  (Optional) userid

Replay mode arguments:
  path/to/replay.osr

Options
-h   --help                   Print this and exit.
     --setting name           Use different danser setting.
     --skin    name           Use different skin.
EOF
	exit 0
	fi
}

help "$@"

getToken() {
	curl -s --request POST "https://osu.ppy.sh/oauth/token" -H "Accept: application/json" -H "Content-Type: application/x-www-form-urlencoded" --data "client_id=${clientID}&client_secret=${clientSecret}&grant_type=client_credentials&scope=public"
}

getRequest() {
	curl -s --request GET --get "$1" --header "Content-Type: application/json" --header "Accept: application/json" --header "x-api-version: 20240529" --header "Authorization: Bearer $token"
}

postRequest() {
	curl -s --request POST "$1" --header "Content-Type: application/json" --header "Accept: application/json" --header "x-api-version: 20240529" --header "Authorization: Bearer $token" --data "$2"
}

getTopPlay() {
	getRequest "https://osu.ppy.sh/api/v2/users/$1/scores/best?limit=1" | jq .[0]
} 

getRecentPlay() {
	getRequest "https://osu.ppy.sh/api/v2/users/$1/scores/recent?limit=1" | jq .[0]
} 

getScore() {
	getRequest "https://osu.ppy.sh/api/v2/scores/$1"
}

getLegacyScore() {
	getRequest "https://osu.ppy.sh/api/v2/scores/$1/$2"
}

getReplay() {
	id="$(jq -r .id <<< "$1")"
	md5="$(jq -r .beatmap.checksum <<< "$1")"
	mkdir -p "$replaydir/$md5/"
	getRequest "https://osu.ppy.sh/api/v2/scores/$id/download" > "$replaydir/$md5/$id.osr"
	printf "$replaydir/$md5/$id.osr"
}

formatPlay() {
	score="$(getBeatmapDiff "$1")"
	star="$(jq -r .beatmap.attributes.star_rating <<< "$score")"
	star="$(bc <<< "scale=2; $star/1")"
	artist="$(jq -r .beatmapset.artist <<< "$score")"
	song="$(jq -r .beatmapset.title <<< "$score")"
	diff="$(jq -r .beatmap.version <<< "$score")"
	mods="$(sortMods "$score")"
	acc="$(jq -r .accuracy <<< "$score")"
	acc="$(bc <<< "scale=2; $acc*100/1")"
	jq 2>&1 > /dev/null -re .pp <<< "$score" && pp="$(jq -r .pp <<< "$score")"
	isfc="$(isFC "$score")"
	
	if [ "$mods" ]
	then
		mods="+$mods "
	fi

	printf 2> /dev/null "⭐%.2f %s - %s [%s] %s%.2f%% %s %.0fpp" "$star" "$artist" "$song" "$diff" "$mods" "$acc" "$isfc" "$pp"
}

sortMods() {
	local mods
	local i
	mods=("AT" "CN" "TD" "TP" "1K" "2K" "3K" "4K" "5K" "6K" "7K" "8K" "9K" "10K" "HO" "NR" "DS" "SR" "DA" "MG" "RP" "FF" "EZ" "FI" "AD" "CS" "CO" "HD" "TC" "DC" "HT" "DF" "GR" "DP" "DT" "NC" "WD" "WU" "AS" "HR" "FR" "BR" "TR" "WG" "SI" "BL" "FL" "ST" "BM" "BU" "IN" "MF" "NS" "SW" "AL" "SG" "AP" "RX" "SO" "AC" "NF" "PF" "SD" "MU" "RD" "SW" "MR" "CL" "SV2" "V2")
	for i in "${mods[@]}"
	do
		for j in $(jq -r .mods\[\].acronym <<< "$1")
		do
			if [ "$j" == "$i" ]
			then
				printf "%s" "$j"
			fi
		done
	done
}

isFC() {
	if jq 2>&1 > /dev/null -re .statistics.miss <<< "$1" 
	then
		printf "%sxMiss" "$(jq -r .statistics.miss <<< "$1")"
	elif jq 2>&1 > /dev/null -re .statistics.large_tick_miss <<< "$1"
	then
		printf "%sxSB" "$(jq -r .statistics.large_tick_miss)"
	elif [ "$(jq 2>&1 > /dev/null -r .accuracy <<< "$1")" == "1.000000" ]
	then
		printf "SS"
	elif [ "$(jq 2> /dev/null -r .is_perfect_combo <<< "$1")" == "true" ]
	then
		printf "PFC"
	else
		printf "FC"
	fi
}

formatReplay() {
	local return
	local i
	local data
	i=0

	log 1>&2 "Parsing replay $1..." 

	# bash cant handle binary data so hashdumped it
	data=($(hexdump "$1" -v -e '1/1 "%02X "'))


	gamemode="$(replayByte "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$gamemode")"
	log 1>&2 "1/16 Game mode"

	version="$(replayNum "$i" 4 "${data[@]}")"
	i="$(jq -r .offset <<< "$version")"
	log 1>&2 "2/16 Version"

	mapMD5="$(replayString "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$mapMD5")"
	log 1>&2 "3/16 Beatmap MD5 hash"

	player="$(replayString "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$player")"
	log 1>&2 "4/16 Player name"

	replayMD5="$(replayString "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$replayMD5")"
	log 1>&2 "5/16 Replay MD5 hash"

	great="$(replayNum "$i" 2 "${data[@]}")"
	i="$(jq -r .offset <<< "$great")"
	log 1>&2 "6/16 Number of greats"

	ok="$(replayNum "$i" 2 "${data[@]}")"
	i="$(jq -r .offset <<< "$ok")"
	log 1>&2 "7/16 Number of oks"

	meh="$(replayNum "$i" 2 "${data[@]}")"
	i="$(jq -r .offset <<< "$meh")"
	log 1>&2 "8/16 Number of mehs"

	# idc about gekis and katus
	i="$(($i+4))"

	miss="$(replayNum "$i" 2 "${data[@]}")"
	i="$(jq -r .offset <<< "$miss")"
	log 1>&2 "9/16 Number of misses"

	score="$(replayNum "$i" 4 "${data[@]}")"
	i="$(jq -r .offset <<< "$score")"
	log 1>&2 "10/16 Total score"

	combo="$(replayNum "$i" 2 "${data[@]}")"
	i="$(jq -r .offset <<< "$combo")"
	log 1>&2 "11/16 Max combo"

	pfc="$(replayByte "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$pfc")"
	log 1>&2 "12/16 Perfect combo"

	mods="$(replayNum "$i" 4 "${data[@]}")"
	i="$(jq -r .offset <<< "$mods")"
	log 1>&2 "13/16 Mods used"

	hpgraph="$(replayString "$i" "${data[@]}")"
	i="$(jq -r .offset <<< "$hpgraph")"
	log 1>&2 "14/16 Life bar graph"

	timestamp="$(replayNum "$i" 8 "${data[@]}")"
	i="$(jq -r .offset <<< "$timestamp")"
	log 1>&2 "15/16 Time stamp"

	replaylen="$(replayNum "$i" 4 "${data[@]}")"
	i="$(jq -r .offset <<< "$replaylen")"

	# wont fit in variable
#	replaydata="$(replayLZMA "$i" "$(jq -r .value <<< "$replaylen")" "${data[@]}")"
#	i="$(jq -r .offset <<< "$replaydata")"
	i="$(($i+$(jq -r .value <<< "$replaylen")))"

	scoreid="$(replayNum "$i" 8 "${data[@]}")"
	i="$(jq -r .offset <<< "$scoreid")"
	log 1>&2 "16/16 Legacy online score ID"

	replaydata="{}"

	if [ "$(jq -r .value <<< "$version")" -ge "30000001" ]
	then
		islazer=1
		lazerlen="$(replayNum "$i" 4 "${data[@]}")"
		i="$(jq -r .offset <<< "$lazerlen")"
		replaydata="$(replayLZMA "$i" "$(jq -r .value <<< "$lazerlen")" "${data[@]}" | jq -r .value)"
		log 1>&2 "Got lazer score data."

		# .online_id to .id
		replaydata="$(jq '.id = .online_id' <<< "$replaydata" | jq 'del(.online_id)')"
	fi

	# ruleset id
	replaydata="$(jq --argjson value "$(jq -r .value <<< "$gamemode")" '.ruleset_id = $value' <<< "$replaydata")"

	# beatmap md5
	replaydata="$(jq --arg value "$(jq -r .value <<< "$mapMD5")" '.beatmap.checksum = $value' <<< "$replaydata")"

	# player name
	replaydata="$(jq --arg value "$(jq -r .value <<< "$player")" '.user.username = $value' <<< "$replaydata")"

	# replay md5 
	replaydata="$(jq --arg value "$(jq -r .value <<< "$replayMD5")" '.checksum = $value' <<< "$replaydata")"

	# statistics
	if [ ! "$islazer" ]
	then
		[ "$(jq -r .value <<< "$great")" == "0" ] || replaydata="$(jq --argjson value "$(jq -r .value <<< "$great")" '.statistics.great = $value' <<< "$replaydata")"
		[ "$(jq -r .value <<< "$ok")" == "0" ] || replaydata="$(jq --argjson value "$(jq -r .value <<< "$ok")" '.statistics.ok = $value' <<< "$replaydata")"
		[ "$(jq -r .value <<< "$meh")" == "0" ] || replaydata="$(jq --argjson value "$(jq -r .value <<< "$meh")" '.statistics.meh = $value' <<< "$replaydata")"
		[ "$(jq -r .value <<< "$miss")" == "0" ] || replaydata="$(jq --argjson value "$(jq -r .value <<< "$miss")" '.statistics.miss = $value' <<< "$replaydata")"
		replaydata="$(jq --argjson value "$(($(jq -r .value <<< "$great")+$(jq -r .value <<< "$ok")+$(jq -r .value <<< "$meh")+$(jq -r .value <<< "$miss")))" '.maximum_statistics.great = $value' <<< "$replaydata")"
	fi

	# accuracy
	replaydata="$(jq --argjson value "$(replayAcc "$(jq -r .statistics <<< "$replaydata")" "$(jq -r .maximum_statistics <<< "$replaydata")")" '.accuracy = $value' <<< "$replaydata")"

	# score
	replaydata="$(jq --argjson value "$(jq -r .value <<< "$score")" '.total_score = $value' <<< "$replaydata")"

	# combo
	replaydata="$(jq --argjson value "$(jq -r .value <<< "$combo")" '.max_combo = $value' <<< "$replaydata")"

	# ispfc
	replaydata="$(jq --argjson value "$([ "$(jq -r .value <<< "$pfc")" == 1 ] && printf "true" || printf "false")" '.is_perfect_combo = $value' <<< "$replaydata")"

	# mods
	[ "$islazer" ] || replaydata="$(jq --argjson mods "$(getMods "$(jq -r .value <<< "$mods")")" '.mods = $mods.mods' <<< "$replaydata")"
		
	# date
	replaydata="$(jq --argjson value "$(jq -r .value <<< "$timestamp")" '.ended_at_tick = $value' <<< "$replaydata")"

	# score id
	[ "$islazer" ] || replaydata="$(jq --argjson value "$(jq -r .value <<< "$scoreid")" '.legacy_score_id = $value' <<< "$replaydata")"

	#replaydata="$(jq --argjson value "$(jq -r .value <<< "$data")" '.key = $value' <<< "$replaydata")"

	printf "$replaydata"



}

getMods() {
# getMods modnum
	local mods=("MR" "V2" "2K" "3K" "1K" "DS" "9K" "TP" "CN" "RD" "FI" "8K" "7K" "6K" "5K" "4K" "PF" "AP" "SO" "AT" "FL" "NC" "HT" "RX" "DT" "SD" "HR" "HD" "TD" "EZ" "NF")
	local num="$(printf "%031d" "$(bc <<< "obase=2; ibase=10; $1")")"
	local i=0
	local c=0
	local nc=0
	local pf=0
	local return='{"mods": []}'
	while true
	do
		if [ "${num:$i:1}" == "1" ]
		then
			[ "${mods[$i]}" == "NC" ] && nc=1
			[ "${mods[$i]}" == "PF" ] && pf=1
			if ! [[ ("${mods[$i]}" == "DT" && "$nc" == "1") || ("${mods[$i]}" == "SD" && "$pf" == "1") ]]
			then
				return="$(jq --arg mod "${mods[$i]}" ".mods[$c].acronym = \$mod" <<< "$return")"
				((c++))
			fi
		fi
		[ ! "${num:$i:1}" ] && break
		((i++))
	done
	printf "%s" "$return"
}

replayAcc() {
# replayAcc .statistics .maximum_statistics	
	local stat="$1"
	local maxstat="$2"
	local i=0
	local hits=(".great" ".ok" ".meh" ".miss" ".large_tick_hit" ".slider_tail_hit" ".count_300" ".count_100" ".count_50" ".count_miss")
	local hitscores=("300" "100" "50" "0" "30" "150" "300" "100" "50" "0")
	local max=0
	local cur=0
	
	for h in "${hits[@]}"
	do
		jq 2>&1 > /dev/null -re "$h" <<< "$maxstat" && max="$(($max+($(jq -r "$h" <<< "$maxstat")*"${hitscores[$i]}")))"
		jq 2>&1 > /dev/null -re "$h" <<< "$stat" && cur="$(($cur+($(jq -r "$h" <<< "$stat")*"${hitscores[$i]}")))"
		((i++))
	done
	printf "%.6f" "$(bc -l <<< "scale=6; $cur/$max")"
}
replayByte() {
# replayByte index arr[@]
	local arr
	local i
	i="$1"
	shift

	arr=("$@")
	byte="$(printf "obase=10; ibase=16; %s\n" "${arr[$i]}" | bc)"
	((i++))
	jq --arg byte "$byte" ".value = \$byte" <<< "{}" | jq --argjson offset "$i" ".offset = \$offset"
}

replayNum() {
# replayNum index length arr[@]
	local arr
	local i
	local len
	local endpos
	i="$1"
	len="$2"
	shift 2

	arr=("$@")
	endpos="$(($i+$len))"
	while ! [ "$i" == "$endpos" ]
	do
		num="${arr[$i]}$num"
		((i++))
	done
	jq --arg num "$(printf "obase=10; ibase=16; %s\n" "$num" | bc)" ".value = \$num" <<< "{}" | jq --argjson offset "$i" ".offset = \$offset"
}

replayString() {
# replayString index arr[@]
	local arr
	local i
	local cur
	local len
	local string
	local endpos
	i="$1"
	shift

	arr=("$@")

	# if string dont exists
	if [ "${arr[$i]}" == "00" ]
	then
		jq ".value = ''" <<< "{}" | jq --argjson offset "$(($i+1))" ".offset = \$offset"
		return 0
	fi
	((i++))

	# length of string, ULEB128
	while true
	do
		# convert to base2 then process
		cur="$(printf "obase=2; ibase=16; %s\n" "${arr[$i]}" | bc)"
		cur="$(printf "%08d" "$cur")"

		# get first char(bit) which indicates if theres more
		read -r -n1 eos <<< "$cur"

		# keep everything except first char
		cur=${cur:1}

		# concatenete backwards
		len="${cur}${len}"
		((i++))
		if [ "$eos" == "0" ]
		then
			break;
		fi
	done
	len="$(printf "obase=10; ibase=2; $len\n" | BC_LINE_LENGTH=0 bc)"

	# actual string, UTF8
	endpos="$(($i+$len))"
	while ! [ "$i" == "$endpos" ]
	do
		string="${string}${arr[$i]}"
		((i++))
	done
	# hex to binary
	string="$(printf "%s" "$string" | xxd -r -p)"
	jq --arg string "$string" ".value = \$string" <<< "{}" | jq --argjson offset "$i" ".offset = \$offset"
}

replayLZMA() {
# replayLZMA index length arr[@]
	local arr
	local i
	local len
	local lzma=""
	i="$1"
	len="$2"
	endpos="$(($i+$len))"
	shift 2

	# LZMA compressed data, in hex
	arr=("$@")
	while ! [ "$i" == "$endpos" ]
	do
		lzma="$lzma${arr[$i]}"
		((i++))
	done

	# hex to binary then decompress
	lzma="$(printf "%s" "$lzma" | xxd -r -p | xz -d -c)"
	jq --arg lzma "$lzma" ".value = \$lzma" <<< "{}" | jq --argjson offset "$i" ".offset = \$offset"

}

getBeatmap() {
	local beatmap
	beatmap="$(getRequest "https://osu.ppy.sh/api/v2/beatmaps/lookup?checksum=$(jq -r .beatmap.checksum <<< "$1")")"
	jq --argjson beatmap "$beatmap" '.beatmap = $beatmap' <<< "$1" | jq '.beatmapset = .beatmap.beatmapset' | jq 'del(.beatmap.beatmapset)'
}

# not realiable yet, it ignores daycore so i had to replace it with halftime, and lazer-specific settings/mods won't work either.
getBeatmapDiff() {
	local attribute
	attribute="$(postRequest "https://osu.ppy.sh/api/v2/beatmaps/$(jq -r .beatmap.id <<< "$1")/attributes" "$(jq --argjson mods "$(jq .mods <<< "$1")" '.mods = $mods' <<< "{}" | jq --argjson ruleset "$(jq -r .ruleset_id <<< "$1")" '.ruleset_id = $ruleset' | sed 's/"DC"/"HT"/g')")"
	jq --argjson attribute "$attribute" '.beatmap.attributes = $attribute.attributes' <<< "$1"
}

getUser() {
	getRequest "https://osu.ppy.sh/api/v2/users/$1"
}

description() {
	if jq 2>&1 > /dev/null -re .user_id <<< "$1"
	then
		userdata="$(getUser "$(jq -r .user_id <<< "$1")")"
	else
		userdata="$(getUser "@$(jq -r .user.username <<< "$1")")"
	fi
	scoreid="$(jq -r .id <<< "$1")"
	username="$(jq -r .username <<< "$userdata")"
	userid="$(jq -r .id <<< "$userdata")"
	rank="$(jq -r .statistics.global_rank <<< "$userdata")"
	country="$(jq -r .statistics.country_rank <<< "$userdata")"
	pp="$(jq -r .statistics.pp <<< "$userdata")"
	pp="$(printf "%.0f" "$pp")"
	accuracy="$(jq -r .statistics.accuracy <<< "$userdata")"
	accuracy="$(bc <<< "scale=2; $accuracy*100")"
	playcount="$(jq -r .statistics.play_count <<< "$userdata")"
	playtime="$(jq -r .statistics.play_time <<< "$userdata")"
	combo="$(jq -r .statistics.maximum_combo <<< "$userdata")"
	max="$(( $(jq -r .statistics.count_300 <<< "$userdata") + $(jq -r .statistics.count_100 <<< "$userdata") + $(jq -r .statistics.count_50 <<< "$userdata") + $(jq -r .statistics.count_miss <<< "$userdata") ))"
	rawacc="$(replayAcc "$(jq -r .statistics <<< "$userdata")" "$(jq --argjson count "$max" '.count_300 = $count' <<< "$userdata")")"
	rawacc="$(bc <<< "scale=2; $rawacc*100")"

	mapartist="$(jq -r .beatmapset.artist <<< "$1")"
	maptitle="$(jq -r .beatmapset.title <<< "$1")"
	mapdiff="$(jq -r .beatmap.version <<< "$1")"
	mapper="$(jq -r .beatmapset.creator <<< "$1")"
	mapsetid="$(jq -r .beatmapset.id <<< "$1")"
	mapid="$(jq -r .beatmap.id <<< "$1")"
	mapruleset="$(jq -r .beatmap.mode <<< "$1")"

	day="$(($playtime/86400))"
	hour="$((($playtime%86400)/3600))"
	min="$((($playtime%3600)/60))"
	sec="$(($playtime%60))"

	topplay="$(formatPlay "$(getTopPlay "$userid")")"
	
	printf "%s (https://osu.ppy.sh/scores/%s)\nPlayed by %s\nhttps://osu.ppy.sh/users/%s\nBeatmap: %s - %s [%s]\nMapped by %s\nhttps://osu.ppy.sh/beatmapsets/%s#%s/%s\n\n%s\nProfile Accuracy: %.2f%% (Raw: %.2f%%)\nPlaytime: %sd %sh %sm %ss\nPlaycount: %s\nMax Combo: %s\nPerformance Point: %spp\nRank: #%s (#%s)\nTop Play: %s" "$scoreid" "$scoreid" "$username" "$userid" "$mapartist" "$maptitle" "$mapdiff" "$mapper" "$mapsetid" "$mapruleset" "$mapid" "$username" "$accuracy" "$rawacc" "$day" "$hour" "$min" "$sec" "$(comma "$playcount")" "$(comma "$combo")" "$(comma "$pp")" "$(comma "$rank")" "$(comma "$country")" "$topplay"
}

completeReplay() {
	if jq 2>&1 > /dev/null -re .id <<< "$1"
	then
		score="$(getScore "$(jq -r .id <<< "$1")")"
	else
		modes=("osu" "taiko" "catch" "mania")
		score="$(getLegacyScore "${modes[$(jq -r .ruleset_id <<< "$1")]}" "$(jq -r .legacy_score_id <<< "$1")")"
	fi
	if jq 2>&1 > /dev/null -re .error <<< "$score"
	then
		error "osu! API returned an error, falling back to using replay data."
		error "Some informations might not be accurate!"
		getBeatmap "$1"
	else
		printf "$score"
	fi
}

# made by chatgpt cuz iam lazy
comma() {
	echo "$1" | rev | sed 's/.\{3\}/&,/g' | rev | sed 's/^,//'
}

# dont think this is secure but idc
if [ -e ~/.cache/Yiriru/osu/token ] && [ "$(date +%s)" -gt "$(($(cat ~/.cache/Yiriru/osu/token | jq -r .timestamp) + $(cat ~/.cache/Yiriru/osu/token | jq -r .expires_in)))" ]
then
	rm ~/.cache/Yiriru/osu/token
fi

if ! [ -e ~/.cache/Yiriru/osu/token ]
then
	mkdir -p ~/.cache/Yiriru/osu/
	getToken | jq --argjson time "$(date +%s)" ".timestamp = \$time" > ~/.cache/Yiriru/osu/token
fi

token="$(cat ~/.cache/Yiriru/osu/token | jq -r .access_token)"

case "$1" in
	'score')
		if ! [ "$2" ]
		then
			error "ID of the score is required!"
			help -h
		fi
		score="$(getScore "$2")"
		replay="$(getReplay "$score")"
		;;
	'recent')
		[ "${2:0:1}" == "-" ] || userid="${2:-$userid}"
		score="$(getRecentPlay "$userid")"
		replay="$(getReplay "$score")"
		;;
	'top')
		[ "${2:0:1}" == "-" ] || userid="${2:-$userid}"
		score="$(getTopPlay "$userid")"
		replay="$(getReplay "$score")"
		;;
	'replay')
		if ! [ "$2" ]
		then
			error "Path to the replay file is required!"
			help -h
		fi
		score="$(formatReplay "$2")"
		score="$(completeReplay "$score")"
		replay="$2"
		;;
	'clear')
		log "$videodir, $replaydir, $beatmapdir"
		log "Cleaning files in 10..."
		sleep 10
		rm -r "$videodir" "$replaydir" "$beatmapdir"
		exit 0
		;;
	*)
		help -h
		;;
esac

setting="$(testOpts '--setting' "$@")"
skin="$(testOpts '--skin' "$@")"

downloadBeatmap "$(jq .beatmapset.id <<< "$score")"
videoname="$(date +%Y-%m-%d_%H-%M-%S)"

# for headless mode
#xvfb-run -d vglrun -d egl0 \
"$dansercli" -replay "$replay" -record ${setting:+-settings $setting} ${skin:+-skin $skin} -out "$videoname"

printf "Rendering is done, video is saved at:\n%s\n" "$videodir/$videoname"

printf "\n\n"
(printf "Video title:\n\n"
formatPlay "$score"
printf "\n\nVideo description:\n\n"
description "$score"
printf "\n") | tee "$videodir/$videoname.txt"

printf "\n\nAlso saved at %s.txt\n" "$videodir/$videoname"
openDir "$videodir"
