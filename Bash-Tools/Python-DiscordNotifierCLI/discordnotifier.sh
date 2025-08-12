#!/bin/bash

#prob dont need this actually but whatever
set -euo pipefail

#Config file path
CONFIG_FILE="./gamevault_config.json"

# server API path (change localhost to your server IP as needed)
API_BASE="http://localhost:8080/api"
#dont touch these unless you know what you're doing
AUTH_BASIC_LOGIN="$API_BASE/auth/basic/login"
USER_ME="$API_BASE/users/me"
GAMES_ENDPOINT="$API_BASE/games"

# File paths - adjust as needed
CURRENT_LIST="./current-list.txt"
NEW_LIST="./new-list.txt"
CHANGELOG="./changelog.log"

#Discord info - adjust as needed
DISCORD_HOOK_URL="webhook URL goes here"
DISCORD_ROLE_ID="<@&roleNumber>"  # Replace with the role/user ID you want to @ in the message (make this a blank string for no @)

# Dependencies check
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required but not installed. Aborting."; exit 1; }

# Load config if exists
username=""
api_key=""

if [ -f "$CONFIG_FILE" ]; then
  username=$(jq -r '.username // empty' "$CONFIG_FILE")
  api_key=$(jq -r '.api_key // empty' "$CONFIG_FILE")
fi

#Get the bot user username/password, basic auth then get API key and store the API key in config file
prompt_for_credentials_and_fetch_key() {
  read -rp "Enter bot username: " username
  read -rsp "Enter bot password: " password
  echo
  basic_auth=$(printf "%s:%s" "$username" "$password" | base64)
  >&2 echo "Logging in to get access_token..."
  access_token=$(curl -s -X GET "$AUTH_BASIC_LOGIN" \
    -H "accept: application/json" \
    -H "Authorization: Basic $basic_auth" | jq -r '.access_token // empty')
  if [ -z "$access_token" ]; then
    echo "Failed to get access_token. Check credentials." >&2
    exit 1
  fi
  >&2 echo "Fetching API key..."
  user_resp=$(curl -s -X GET "$USER_ME" \
    -H "accept: application/json" \
    -H "Authorization: Bearer $access_token")
  api_key=$(echo "$user_resp" | jq -r '.api_key // empty')
  if [ -z "$api_key" ]; then
    echo "Failed to retrieve API key." >&2
    exit 1
  fi
  jq -n --arg user "$username" --arg key "$api_key" '{username: $user, api_key: $key}' > "$CONFIG_FILE"
  >&2 echo "API key saved to $CONFIG_FILE."
}

if [ -z "$api_key" ]; then
  prompt_for_credentials_and_fetch_key
fi

#Get all the games yehaw
fetch_all_games_with_versions() {
  local page=1
  local results=()
  >&2 echo "Fetching all game titles with versions..."
  while :; do
    >&2 echo "Fetching page $page..."
    response=$(curl -s -G "$GAMES_ENDPOINT" \
      --data-urlencode "page=$page" \
      --data-urlencode "sortBy=title:ASC" \
      -H "accept: application/json" \
      -H "X-Api-Key: $api_key")
    if [ -z "$response" ]; then
      >&2 echo "Empty response from API on page $page, stopping."
      break
    fi
    count=$(echo "$response" | jq -r 'if has("data") then (.data | length) else 0 end' 2>/dev/null || echo 0)
    if [[ "$count" == "0" ]]; then
      break
    fi
    page_results=$(echo "$response" | jq -r '.data[] | "\(.title)|\(.version // "")"')
    results+=("$page_results")
    ((page++))
  done
  printf '%s\n' "${results[@]}"
}

#Do it agian but different
fetch_all_games_with_covers() {
  local page=1
  local games_json="[]"
  >&2 echo "Fetching all games with covers and URLs for embed..."
  while :; do
    response=$(curl -s -G "$GAMES_ENDPOINT" \
      --data-urlencode "page=$page" \
      --data-urlencode "sortBy=title:ASC" \
      -H "accept: application/json" \
      -H "X-Api-Key: $api_key")
    count=$(echo "$response" | jq -r 'if has("data") then (.data | length) else 0 end' 2>/dev/null || echo 0)
    if [[ "$count" == "0" ]]; then break; fi

    page_items=$(echo "$response" | jq '.data | map({
      title: .title,
      version: (.version // ""),
      cover: (.metadata.cover.source_url // ""),
      url: (if (.metadata.provider_data_url // "") == "" then null else .metadata.provider_data_url end)
    })')
    # Combine existing games_json and page_items arrays
    games_json=$(printf '%s\n%s\n' "$games_json" "$page_items" | jq -s 'add')
    ((page++))
  done
  echo "$games_json"
}

#Check if the current-list.txt file exists and make it if not
if [ ! -f "$CURRENT_LIST" ]; then
  echo "No current list found, fetching initial list of games..."
  fetch_all_games_with_versions > "$CURRENT_LIST"
  echo "Initial list created. Will look for changes on next run!"
  exit 0
fi

#If current-list.txt already exists, go ahead and pull the "new list" of games to compare
echo "Fetching new list for comparison..."
fetch_all_games_with_versions > "$NEW_LIST"

echo "Comparing lists..."

# Load current and new lists into associative arrays mapping title->version
declare -A current_versions
declare -A new_versions

while IFS='|' read -r title version; do
  current_versions["$title"]="$version"
done < "$CURRENT_LIST"

while IFS='|' read -r title version; do
  new_versions["$title"]="$version"
done < "$NEW_LIST"

added=()
removed=()
updated=()

# Determine removed
for title in "${!current_versions[@]}"; do
  if [[ -z "${new_versions[$title]+_}" ]]; then
    removed+=("$title")
  fi
done

# Determine added and updated
for title in "${!new_versions[@]}"; do
  if [[ -z "${current_versions[$title]+_}" ]]; then
    added+=("$title")
  else
    old_version="${current_versions[$title]}"
    new_version="${new_versions[$title]}"
    if [[ "$old_version" != "$new_version" ]]; then
      updated+=("$title|$old_version|$new_version")
    fi
  fi
done

if [ ${#added[@]} -eq 0 ] && [ ${#removed[@]} -eq 0 ] && [ ${#updated[@]} -eq 0 ]; then
  echo "No changes detected."
  rm -f "$NEW_LIST"
  exit 0
fi

echo "Changes detected!"

#update the changelog as needed
echo "Writing changes to changelog..."
{
  echo "Date/Time: $(date '+%Y-%m-%d %H:%M:%S')"
  if [ ${#added[@]} -gt 0 ]; then
    echo -e "\nGames added:"
    for game in "${added[@]}"; do
      echo "$game"
    done
    echo ""
  fi
  if [ ${#removed[@]} -gt 0 ]; then
    echo -e "\nGames removed:"
    for game in "${removed[@]}"; do
      echo "$game"
    done
    echo ""
  fi
  if [ ${#updated[@]} -gt 0 ]; then
    echo -e "\nGames updated:"
    for entry in "${updated[@]}"; do
      IFS='|' read -r title old_ver new_ver <<< "$entry"
      echo "$title - $old_ver > $new_ver"
    done
    echo ""
  fi
  echo "----------------------------------------"
} >> "$CHANGELOG"
echo "Changelog updated."

echo "Updating current list..."
mv "$NEW_LIST" "$CURRENT_LIST"
echo "Current list updated."

rm -f "$NEW_LIST"
echo "Temporary new list removed."

echo "Fetching data with covers for Discord embeds..."
games_json=$(fetch_all_games_with_covers 2>/dev/null)

declare -A cover_map
declare -A url_map
mapfile -t titles_arr < <(echo "$games_json" | jq -r '.[].title')
mapfile -t covers_arr < <(echo "$games_json" | jq -r '.[].cover')
mapfile -t urls_arr < <(echo "$games_json" | jq -r '.[].url')

for i in "${!titles_arr[@]}"; do
  cover_map["${titles_arr[$i]}"]="${covers_arr[$i]}"
  url_map["${titles_arr[$i]}"]="${urls_arr[$i]}"
done

embeds=$(jq -n '[]')

# Build added embeds (green)
for title in "${added[@]}"; do
  cover_url=${cover_map["$title"]:-""}
  link_url=${url_map["$title"]:-""}
  if [ -n "$cover_url" ]; then
    cover_json=$(jq -n --arg url "$cover_url" '{url: $url}')
  else
    cover_json="null"
  fi
  embed=$(jq -n --arg title "$title" --argjson image "$cover_json" --arg url "$link_url" '{
    title: $title,
    url: (if $url == "" then null else $url end),
    color: 3046983,
    image: $image
  }')
  embeds=$(echo "$embeds" | jq --argjson e "$embed" '. + [$e]')
done

# Build updated embeds (yellow)
for entry in "${updated[@]}"; do
  IFS='|' read -r title old_ver new_ver <<< "$entry"
  cover_url=${cover_map["$title"]:-""}
  link_url=${url_map["$title"]:-""}
  if [ -n "$cover_url" ]; then
    cover_json=$(jq -n --arg url "$cover_url" '{url: $url}')
  else
    cover_json="null"
  fi
  description="Updated from version $old_ver to $new_ver"
  embed=$(jq -n --arg title "$title" --arg desc "$description" --argjson image "$cover_json" --arg url "$link_url" '{
    title: $title,
    url: (if $url == "" then null else $url end),
    description: $desc,
    color: 16776960,
    image: $image
  }')
  embeds=$(echo "$embeds" | jq --argjson e "$embed" '. + [$e]')
done

# Build removed embed (red, text only)
if [ ${#removed[@]} -gt 0 ]; then
  removed_text=$(printf '%s\n' "${removed[@]}" | sed 's/"/\\"/g')
  embed_removed=$(jq -n --arg desc "$removed_text" '{
    title: "Games Removed",
    description: $desc,
    color: 15158332
  }')
  embeds=$(echo "$embeds" | jq --argjson e "$embed_removed" '. + [$e]')
fi

if [ "$embeds" = "[]" ]; then
  echo "No changes to notify."
  exit 0
fi

#send the notification
payload=$(jq -n --arg content "$DISCORD_ROLE_ID" --argjson embeds "$embeds" '{content: $content, embeds: $embeds}')

echo "Sending Discord notification..."
curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_HOOK_URL"
echo "Discord notification sent."

echo "Script completed successfully."
