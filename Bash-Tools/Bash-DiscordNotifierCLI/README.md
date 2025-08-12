# Discord Notifier CLI
Uses GameVault bot user (via basic auth and API key) to check the games and send Discord webhook message to notify for the following:

* Games Added (name, cover image, link to igdb page)
* Games Updated (name, cover image, link to igdb page, what version it WAS and now IS)
* Games Removed (text only, as needed)

****
# Variables that you can modify in the script

CONFIG_FILE - set to path where you want the changelog file to be saved (persistent)

API_BASE="http://localhost:8080/api" - change the "localhost" part to your server IP if needed

CURRENT_LIST - set to the path where you want the "current-list.txt" file (your game list) to be saved (persistent)

NEW_LIST - set to the path where you want the temporarly "new-list.txt" file to be saved (removed after each run)

CHANGELOG - set to the path where you want the changelog to be saved

DISCORD_HOOK_URL - put your webhook URL here

DISCORD_ROLE_ID - Set this to be your user/role ID so the message includes an @ if desired
****
# Setup Needed:
For this to work, you will need to do a few things first.

1. Allow API logins on your server: https://gamevau.lt/docs/advanced-usage/authentication/#enabling-api-key-support
2. Create a bot user on your server - something like "gvbot_discordnotifier"
3. Configure Discord webhook integration: https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks
4. Configure script as needed - and make sure you have curl and jq install
5. Run the script!

****
# How does this work?
* run the script and you will be prompted for the bot username and password
* script will then basic auth to your server, grab the bot user's API key, and save the key into the config file
* subsequent runs will use the API key - keep this safe
* Initial run of the script will pull all games from your server, store a list of these games.
* Future runs will pull the list again, compare the new list to the current list, make list of changes, and send Discord notif with those changes!

****
# How does it look?
Like this (redacted for privacy):

<img width="589" height="679" alt="image" src="https://github.com/user-attachments/assets/17e1eec8-e70a-4250-b2b8-b8efc150a76a" />


