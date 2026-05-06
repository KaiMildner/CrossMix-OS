#!/bin/ash

governor="$1"
min_id="$2"
max_id="$3"
active_cores="$4"

AVAILABLE_FREQS=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null)
if [ -z "$AVAILABLE_FREQS" ]; then
	AVAILABLE_FREQS="408000 600000 816000 1008000 1200000 1416000 1608000 1800000 2000000"
fi
FREQ_LIST=$(echo "$AVAILABLE_FREQS" | tr ' ' '\n' | sort -n | tr '\n' ' ')
MAX_ID=$(echo "$FREQ_LIST" | wc -w | tr -d ' ')
MAX_ID=$((MAX_ID - 1))

id_to_freq() {
	echo "$FREQ_LIST" | tr ' ' '\n' | sed -n "$((${1} + 1))p"
}

freq_to_id() {
	local target="$1"
	local i=0
	for f in $FREQ_LIST; do
		[ "$f" = "$target" ] && echo $i && return
		i=$((i + 1))
	done
}

# display current CPU settings and usage examples
show_info() {
	read current_governor </sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	read current_min_freq </sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
	read current_max_freq </sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq

	min_id=$(freq_to_id "$current_min_freq")
	max_id=$(freq_to_id "$current_max_freq")

	num_cores=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
	active_count=$(grep -h ^1$ /sys/devices/system/cpu/cpu*/online 2>/dev/null | wc -l)


	cat <<-EOF
		========================================================================
		Usage examples:
		---------------
		  cpufreq.sh performance 3 7    # Set governor to 'performance', only max freq will be applied to 1800000 kHz
		  cpufreq.sh ondemand 1 5       # Set governor to 'ondemand', min freq to 600000 kHz, max freq to 1416000 kHz
		  cpufreq.sh ondemand 1 5 2     # Set governor to 'ondemand', min freq to 600000 kHz, max freq to 1416000 kHz, 2 cores enabled
		  cpufreq.sh powersave 0 2      # Set governor to 'powersave', min freq to 408000 kHz, max freq to 816000 kHz
		========================================================================
		Current CPU settings:
		---------------------
		  Governor: $current_governor
		  Min Frequency: $min_id = ${current_min_freq} kHz
		  Max Frequency: $max_id = ${current_max_freq} kHz
		  Active Cores: $active_count / $num_cores
		========================================================================
	EOF
}

# without arguments, display current cpu settings and examples
if [ -z "$governor" ]; then
	show_info
	exit 0
fi

# Validate frequency settings
if [ "$governor" != "interactive" ] && [ "$governor" != "ondemand" ] && [ "$governor" != "performance" ] && [ "$governor" != "powersave" ] && [ "$governor" != "conservative" ]; then
	echo "cpufreq.sh: Invalid governor."
	exit 1
elif [ $min_id -lt 0 ] || [ $min_id -gt $MAX_ID ]; then
	echo "cpufreq.sh: Invalid min frequency ID."
	exit 1
elif [ $max_id -lt $min_id ] || [ $max_id -gt $MAX_ID ]; then
	echo "cpufreq.sh: Invalid max frequency ID."
	exit 1
fi

# Validate core count if provided
if [ -n "$active_cores" ]; then
	total_cores=$(ls -d /sys/devices/system/cpu/cpu[0-3]* 2>/dev/null | wc -l)
	if [ "$active_cores" -lt 1 ] || [ "$active_cores" -gt "$total_cores" ]; then
		echo "cpufreq.sh: Invalid active core count."
		exit 1
	fi
fi

min_freq=$(id_to_freq $min_id)
max_freq=$(id_to_freq $max_id)

echo "Setting CPU frequency to $governor, $min_freq - $max_freq kHz."

# Apply frequency settings
echo $governor >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
if [ $min_freq -gt "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)" ]; then
	echo $max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	echo $min_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
else
	echo $min_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
	echo $max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
fi

# Optionally set number of active CPU cores
if [ -n "$active_cores" ]; then
	i=0
	for cpu_path in /sys/devices/system/cpu/cpu[0-3]*; do
		cpu_id=$(basename $cpu_path | sed 's/cpu//')
		if [ "$i" -lt "$active_cores" ]; then
			echo 1 > "$cpu_path/online" 2>/dev/null
		else
			echo 0 > "$cpu_path/online" 2>/dev/null
		fi
		i=$((i + 1))
	done
	echo "Activated $active_cores CPU core(s)."
fi
