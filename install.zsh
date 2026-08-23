#!/usr/bin/env zsh

emulate -LR zsh
setopt NO_UNSET PIPE_FAIL

readonly SOURCE_DIRECTORY=${0:A:h}
readonly SOURCE_FILE="${SOURCE_DIRECTORY}/git-wt"
readonly DESTINATION_DIRECTORY="${HOME}/.local/bin"
readonly DESTINATION_FILE="${DESTINATION_DIRECTORY}/git-wt"

if ! mkdir --parents -- "$DESTINATION_DIRECTORY"; then
  print -ru2 -- "git-wt installer: could not create ${DESTINATION_DIRECTORY}"
  exit 1
fi

if ! install --mode=0755 -- "$SOURCE_FILE" "$DESTINATION_FILE"; then
  print -ru2 -- "git-wt installer: could not install ${DESTINATION_FILE}"
  exit 1
fi

print -r -- "Installed ${DESTINATION_FILE}"
