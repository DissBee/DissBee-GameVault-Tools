#! /bin/bash

# if you are seeing this, good job for not trusting random scripts!

# set up virtual environ for python and install needed stuff
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# run the actual script
python gamevault-lister-python.py
