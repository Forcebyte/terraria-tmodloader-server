#!/bin/bash
set -u

create-config.sh

console_fifo=/tmp/tml-console
rm -f "$console_fifo"
mkfifo "$console_fifo"

cleanup() {
	exec 3>&-
	rm -f "$console_fifo"
}

stop_server() {
	echo "Sending save and exit commands to tModLoader" >&2
	printf 'save\nexit\n' >&3 2>/dev/null || true
	wait "$server_pid"
	status=$?
	cleanup
	exit "$status"
}

./manage-tModLoaderServer.sh docker --folder /home/tml/.local/share/Terraria/tModLoader < "$console_fifo" &
server_pid=$!
exec 3>"$console_fifo"
rm -f "$console_fifo"
trap stop_server TERM INT

wait "$server_pid"
status=$?
cleanup
exit "$status"