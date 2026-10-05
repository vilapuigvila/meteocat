#!/bin/bash

API_KEY="7r5zloC5zs2MjyxAfdnkd1cvuUeKpvWQ9cONyuPh"
BASE_URL="https://api.meteo.cat/xema/v1/variables/mesurades"

echo "[" > all_metadades.json

for i in {1..2}
do
  echo "Fetching metadata for variable $i..."
  RESPONSE=$(curl -s -X GET "${BASE_URL}/${i}/metadades" \
                    -H "x-api-key: ${API_KEY}")
  
  echo "${RESPONSE}" >> all_metadades.json

  if [ "$i" -lt 100 ]; then
    echo "," >> all_metadades.json
  fi
done

echo "]" >> all_metadades.json

# Open the file with the default application (macOS)
of all_metadades.json

# For Linux (uncomment this line if using Linux)
# xdg-open all_metadades.json
