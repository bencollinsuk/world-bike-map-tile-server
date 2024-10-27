#!/bin/bash

while [ ! -f "$1" ]; do
  echo "wait-for-file.sh: Waiting for $1..."
  sleep 1
done

echo "wait-for-file.sh: Found $1"

