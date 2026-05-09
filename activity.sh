#!/bin/bash

# Navigate to your repository directory
cd /path/to/your/repo

# Create an empty commit with a message including the current date
git commit --allow-empty -m "Daily commit $(date +'%Y-%m-%d')"

# Push the commit to the main branch (or the branch you want to track)
git push origin main
