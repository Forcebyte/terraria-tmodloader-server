#!/bin/bash
create-config.sh

if [[ -t 0 && -t 1 ]]; then
	 exec tmux new-session -s "tml" ./manage-tModLoaderServer.sh docker --folder /home/tml/.local/share/Terraria/tModLoader
else
	 exec ./manage-tModLoaderServer.sh docker --folder /home/tml/.local/share/Terraria/tModLoader
fi