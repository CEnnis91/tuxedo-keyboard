#!/bin/bash
# tuxedo_controller - controller script to manage tuxedo_keyboard

SELF_NAME="$(basename "$0" ".sh")"
MODULE="tuxedo_keyboard"

MODPROBE_PATH="/etc/modprobe.d/${MODULE}.conf"
DEVICE_PATH="/sys/devices/platform/${MODULE}"
# shellcheck disable=SC2034
MODULE_PATH="/sys/module/${MODULE}"

RUN_DIR="/run/${MODULE}"
LOCKED_PATH="${RUN_DIR}/${SELF_NAME}.locked"
PID_PATH="${RUN_DIR}/${SELF_NAME}.pid"

__get_param() {
        local type="$1"
        local name="$2"
        local prefix=""

        # add a hex identifier for color parameters
        if [[ "$name" =~ ^color.*$ ]]; then
                prefix="0x"
        fi

	local value=""
        if [[ "$type" == "live" ]]; then
                value="${prefix}$(cat "${DEVICE_PATH}/${name}")"
        else
                value="${prefix}$(cat "${RUN_DIR}/${name}")"
        fi

	if [[ "$name" =~ ^color.*$ ]]; then
		value="$(echo "$value" | grep -o "0x[A-Fa-f0-9]\{6\}$")"
	fi

	echo "$value"
}
get_live_param() { __get_param "live" "$1" ; }
get_temp_param() { __get_param "temp" "$1" ; }

__set_param() {
        local type="$1"
        local name="$2"
        local value="$3"
        local prefix=""

        # add a hex identifier for color parameters
        if [[ "$name" =~ ^color.*$ ]]; then
                prefix="0x"
                value="$(echo "$value" | grep -o "0x[A-Fa-f0-9]\{6\}$")"
        fi

        if [[ "$type" == "live" ]]; then
                echo "${prefix}${value}" > "${DEVICE_PATH}/${name}"
        else
                echo "${prefix}${value}" > "${RUN_DIR}/${name}"
        fi
}
set_live_param() { __set_param "live" "$1" "$2" ; }
set_temp_param() { __set_param "temp" "$1" "$2" ; }


blink_leds() {
        local count="$1"
        local speed_on="${2:-0.25}"
        local speed_off="${3:-0.25}"

        local original
        original="$(get_live_param "state")"

        for ((n = 0; n < "$count"; n++)); do
                set_live_param "state" "1"
                sleep "$speed_on"

                set_live_param "state" "0"
                sleep "$speed_off"
        done
        set_live_param "state" "$original"
}

help_message() {
        local file
        file="$(sed '/^case.*/,/^esac/p' "$0")"
        local args
        args="$(echo "$file" | grep "[A-Za-z_]\+[)]" | grep -v "grep" | cut -d')' -f1 | sort | uniq | xargs)"
        echo -e "${SELF_NAME} [action]\nActions: ${args}"
}

fade_brightness() {
        local fade_to="$1"
        local fade_from
        fade_from="$(get_live_param "brightness")"

        local rate="${2:-3}"

	for n in $(eval echo "{${fade_from}..${fade_to}..${rate}}"); do
		set_live_param "brightness" "$n"
	done
	set_live_param "brightness" "$fade_to"
}

log_action() {
	logger -t "$SELF_NAME" "$1"
}

module_exists() {
	echo "$(modinfo "${1}" &>/dev/null; echo $?)"
}

monitor_screen() {
	# check to see if there's an active monitor
	if [[ -f "$PID_PATH" ]]; then
		CURRENT_PID="$(cat "$PID_PATH")"
		if ps -p "$CURRENT_PID" > /dev/null; then
			return 0
		fi
	fi

	# mark the device as unlocked by default
	echo "$$" > "$PID_PATH"

	gdbus monitor --system --dest org.freedesktop.login1 | while read -r signal; do
		# display has been blanked
		if [[ "$signal" =~ .*LockedHint.*true.* ]]; then
			log_action "Device locked, fading brightness to 0"
			preserve_state "$MODULE" "temp"

			if [[ "$(get_live_param "state")" == "1" ]]; then
				fade_brightness "0"
			fi

			# mark the device as locked
                        echo "1" > "$LOCKED_PATH"
		fi

		# display has been unblanked
		if [[ "$signal" =~ .*LockedHint.*false.* ]]; then
			log_action "Device unlocked, restoring brightness to $(get_temp_param "brightness")"

			if [[ "$(get_temp_param "state")" == "1" ]]; then
				fade_brightness "$(get_temp_param "brightness")"
			fi

			# mark the device as unlocked
			rm -f "$LOCKED_PATH"
		fi
	done
}

preserve_state() {
	local params
        params="$(modinfo -p "${1}" | cut -d':' -f1)"

        local temp="${2:-0}"
	local shutdown="${3:-0}"

        if [[ "$temp" == "0" ]]; then
                local param_conf="options ${1}"

        	for param in $params; do
			# if the device is locked, get the temp state, not the live state
			if [[ -f "$LOCKED_PATH" ]]; then
				log_action "Pulling $param from temp"
				param_conf="${param_conf} ${param}=$(get_temp_param "$param")"

				if [[ -z "$(get_temp_param "$param")" ]]; then
					return 1
				fi
			else
				log_action "Pulling $param from live"
				param_conf="${param_conf} ${param}=$(get_live_param "$param")"

				if [[ -z "$(get_live_param "$param")" ]]; then
					return 1
				fi
			fi
	        done

		log_action "Preserving ${1} state: '${param_conf}'"
                echo "$param_conf" > "$MODPROBE_PATH"

		if [[ "$shutdown" == "1" ]]; then
			fade_brightness "0"
		fi
        else
                for param in $params; do
                        get_live_param "$param" > "${RUN_DIR}/${param}"
                done
        fi
}

restore_state() {
	log_action "Restoring ${1} from preserved state"

        fade_brightness "0"
        rmmod "$1"
        modprobe "$1"
}

# quietly exit the module does not exist
if [[ "$(module_exists "$MODULE")" != "0" ]]; then
	exit 0
fi
mkdir -p "$RUN_DIR"

case "$1" in
        blink_fast)     blink_leds "$2" "0.25" "0.25" ;;
        blink_slow)     blink_leds "$2" "0.50" "0.50" ;;
        fade_in)        set_live_param "state" "$(get_temp_param "state")"
                        fade_brightness "$(get_temp_param "brightness")"
                        ;;
        fade_out)       preserve_state "$MODULE" "temp"
                        fade_brightness "0"
                        ;;
	monitor)	monitor_screen ;;
        preserve)       preserve_state "$MODULE" ;;
	preserve_off)	preserve_state "$MODULE" "0" "1" ;;
        restore)        restore_state "$MODULE" ;;
        *)              help_message ;;
esac

exit 0
