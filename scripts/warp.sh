#!/bin/bash

set -e

# Kill any existing instances of warp-svc before starting a new one
if pkill -x warp-svc -9; then
  echo "Existing warp-svc process killed."
fi

# Start warp-svc in the background and redirect output to exclude dbus messages
warp-svc > >(grep -iv dbus) 2> >(grep -iv dbus >&2) &
WARP_PID=$!

# Trap SIGTERM and SIGINT, and forward those signals to the warp-svc process
trap "echo 'Stopping warp-svc...'; kill -TERM $WARP_PID; exit" SIGTERM SIGINT

# Maximum number of attempts to try the registration
MAX_ATTEMPTS=5
attempt_counter=0

echo "Attempting to start warp-svc and register..."

# Function to wait for warp-svc to start
function wait_for_warp_svc {
  until warp-cli --accept-tos status &> /dev/null; do
    echo "Wait for warp-svc to start... Attempt $((++attempt_counter)) of $MAX_ATTEMPTS"
    sleep 1
    if [[ $attempt_counter -ge $MAX_ATTEMPTS ]]; then
      echo "Failed to start warp-svc after $MAX_ATTEMPTS attempts. Exiting."
      exit 1
    fi
  done
  echo "warp-svc started successfully!"
}

# Wait for warp-svc to start
if wait_for_warp_svc; then
  echo "warp-svc has been started successfully!"
else
  echo "There was an issue starting the service. Check logs for details."
  kill $WARP_PID
  exit 1
fi

# Check if registration is already obtained before with warp-cli registration show
warp-cli --accept-tos registration show &> /dev/null
  if [[ $? -ne 0 ]]; then
    echo "Registering service ... "
    warp-cli --accept-tos registration new &> /dev/null
  fi

# Set the proxy port to 40000
warp-cli --accept-tos proxy port 40000

# Set the mode to proxy
warp-cli --accept-tos mode proxy

# Disable DNS log
warp-cli --accept-tos dns log disable

# Set the families mode based on the value of the FAMILIES_MODE variable
warp-cli --accept-tos dns families "${FAMILIES_MODE}"

# Set the WARP_LICENSE if it is not empty
if [[ -n $WARP_LICENSE ]]; then
  warp-cli --accept-tos registration license "${WARP_LICENSE}"
fi

# Connect to the WARP service
warp-cli --accept-tos connect

while true; do
  # Check if warp-cli is connected
  if warp-cli --accept-tos status | grep -iq connected; then
    echo "Connected successfully."
    # If connected, start healthcheck and break the loop
    supervisorctl start healthcheck
    break
  else
    echo "Not connected. Checking again..."
  fi
  # Wait for a specified time before checking again
  sleep 1
done

# Wait for warp-svc process to finish
wait $WARP_PID
