# Arlo Utilities for Ruby

Provides a few features for interacting with Arlo:

- Authentication with MFA via direct E-mail access via IMAP or token prompt through the console
- List and describe base station and cameras
- Stream video from the cloud using (with ffmpeg + VLC)
- Remote Access To Local Station (RATLS) to actually interact with APIs on the Base Station.
  - Provides media downloads directly from local storage (not all recording make it to the cloud!)
  - Streaming from base station *hopefully* coming soon (need SSL context controls with RTSPS, which no one provides)

## Warning _Very Experimental_

I am open to any contributions!
