
eval `ssh-agent`
ssh-add ~/.ssh/google_compute_engine

# The following credentials are prepared for MagFS:

export GC_ACCESS_KEY=YOUR_GOOGLE_ACCESS_KEY
export GC_SECRET_KEY=YOUR_GOOGLE_SECRET_KEY
# Below can be a random name (all lower cases)
export GC_CONTAINER=scratch
