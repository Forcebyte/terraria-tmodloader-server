FROM teriyakigod/steamcmd:arm64

USER root

# Install prerequisites
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
	 bash \
	 curl \
	 unzip \
	 libstdc++6 \
	 libgcc-s1 \
	 libicu-dev \
 && rm -rf /var/lib/apt/lists/*

# Set a specific tModLoader version, defaults to the latest Github release
ARG TML_VERSION

# Create tModLoader user and drop root permissions
ARG UID=1000
ARG GID=1000
RUN existing_group=$(getent group "$GID" | cut -d: -f1) \
 && if [ -z "$existing_group" ]; then \
			groupadd --gid "$GID" tml; \
		elif [ "$existing_group" != "tml" ]; then \
			groupmod --new-name tml "$existing_group"; \
		fi \
 && existing_user=$(getent passwd "$UID" | cut -d: -f1) \
 && if [ -z "$existing_user" ]; then \
			useradd --uid "$UID" --gid tml --create-home --home-dir /home/tml --shell /bin/bash tml; \
		elif [ "$existing_user" != "tml" ]; then \
			usermod --login tml --uid "$UID" --gid tml --home /home/tml --move-home "$existing_user"; \
		fi

# The ARM64 base image provides SteamCMD through FEXBash under /home/steam.
# SteamCMD updates its own files, so move the base image's trees into the
# runtime user's home and give tml ownership of the complete FEX environment.
RUN mv /home/steam/Steam /home/tml/Steam \
 && mv /home/steam/.fex-emu /home/tml/.fex-emu \
 && chown -R tml:tml /home/tml/Steam /home/tml/.fex-emu \
 && chmod 755 /home/tml /home/tml/Steam /home/tml/.fex-emu \
 /home/tml/.fex-emu/RootFS /home/tml/.fex-emu/RootFS/Ubuntu_22_04 \
 && printf '%s\n' '#!/bin/sh' 'cd /home/tml/Steam || exit 1' 'DEBUGGER=FEXBash exec FEXBash ./steamcmd.sh "$@"' \
	> /usr/local/bin/steamcmd \
 && chmod 755 /usr/local/bin/steamcmd

USER tml
ENV USER=tml
ENV HOME=/home/tml
# FEX uses the root filesystem supplied by the ARM64 base image.
ENV FEX_ROOTFS=/home/tml/.fex-emu/RootFS/Ubuntu_22_04
WORKDIR $HOME

# Keep runtime scripts outside the tModLoader data directory. The latter is
# commonly bind-mounted or backed by a PVC and can hide files baked into the image.
ENV SCRIPTS_PATH="/home/tml/scripts"
ENV PATH="${SCRIPTS_PATH}:${PATH}"

# Using Environment variables for server config by default. If you would like to use a serverconfig.txt file instead, uncomment the following variable or use it in your docker-compose.yml environment section.
# ENV USE_CONFIG_FILE=1

# Environment variables for server settings
ENV WORLD=""
ENV AUTOCREATE="1"
ENV SEAD=""
ENV WORLDNAME="tmlWorld.wld"
ENV DIFFICULTY="1"
ENV MAXPLAYERS="16"
ENV PORT="7777"
ENV PASSWORD=""
ENV MOTD=""
ENV WORLDPATH="/home/tml/.local/share/Terraria/tModLoader/Worlds/"
ENV BANLIST="banlist.txt"
ENV SECURE="0"
ENV LANGUAGE="en/US"
ENV UPNP="1"
ENV NPCSTREAM="1"
ENV PRIORITY=""

# ENV MODPATH="/home/tml/.local/share/Terraria/tModLoader/Mods/"

# ADD --chown=tml:tml https://raw.githubusercontent.com/tModLoader/tModLoader/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/manage-tModLoaderServer.sh .

# If you need to make local edits to the management script copy it to the same
# directory as this file, comment out the above line and uncomment this line:
COPY --chown=tml:tml manage-tModLoaderServer.sh .

# Do not place these scripts under the tModLoader data directory: it is mounted
# over at runtime and would otherwise hide the image's entrypoint.
COPY --chown=tml:tml tModLoader/Scripts/ /home/tml/scripts/
RUN chmod 755 /home/tml/scripts/*.sh /home/tml/scripts/inject

RUN if [ -n "$TML_VERSION" ]; then \
		./manage-tModLoaderServer.sh install-tml --github --tml-version "$TML_VERSION"; \
	else \
		./manage-tModLoaderServer.sh install-tml --github; \
	fi

EXPOSE 7777

ENTRYPOINT [ "/home/tml/scripts/entrypoint.sh" ]