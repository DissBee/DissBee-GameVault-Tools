# gamevault-lister-python

This is a cheap knockoff of https://github.com/Toylerrr/Smoke-Launcher

Stupid python script that auths you to your GameVault server, lists all the games, and lets you download em to run through whatever means you wanna run em.

This script exists for me to grab games from my instance and run em through lutris or whatever - It will not be modified further or supported in any way.


# Config File Details
A config json will be generated after you auth for the first time. It stores your server address, username, and chosen download directory. 

You will have to entire password each time, and it will time out after 5 min requiring a reauth

# Security note
Run at your own risk - I am not responsible for how this script handles your credentials.

if you want a proper program check out Smoke-Launcher or the official GameVault client.



# How to use this
clone the repo - cd into the directory - run the "autolaunch.sh" if you're feeling dangerous.

Alternatively, you can do the following:

<code> python -m venv venv && source venv/bin/activate </code>

note - this is for bash - other shells need other activates. Example, for fish, would be venv/bin/activate.fish

<code> pip install -r requirements.txt </code>

This installs the required packages into your virtual environment

<code> python gamevault-lister-python.py </code>

There ya go!

# It looks like this:

<img width="748" height="789" alt="image" src="https://github.com/user-attachments/assets/9b5931e8-b74b-4464-9f07-5b0ba4cdd5fa" />


