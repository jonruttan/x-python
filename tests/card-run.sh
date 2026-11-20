#!/bin/sh
# card-run.sh FILE -- run one program of docs/card.md, as the card check asks.
exec "${X:-x}" -l python -f "$1"
