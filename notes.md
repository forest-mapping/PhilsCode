# Notes

## Meeting Notes
November 10th
- Check if we need to use every R Script
- We left off working on 02_Extract_CHM_NAIP_serial.R.  We may not need part or all of it
- Will meet the same time next week
- Shared CLI and Python package on GitHub

December 1
- What about caching of outputs?  Should considering adding caching
- Should be able to cache output files and input data
- Temporary storage of intermediate files?
- Need to able to pass a directory of files 
    - [x] Runtime should be able to rename the folder
    - [x] The connectors should be able to handle the directory
    - [x] The `psaed` daemon process should be able to handle the directory
    - [ ] The connector should upload all files in the directories returned to the runtime







## Thoughts for Later
For later: 
- It's likely we will want to re-write the daemon in a compiled language
    - Go looks nice; we could write the entire thing end-to-end in Go (We app in TS/Vue still).  
    - Go has good connectors for R
    - Go and Python can work together; the current version uses uv anyway, so it's less of an issue here. 
    - Another option is to make a version of uv for R, which would be great but a lot of work.  The R ecosystem....
- Storing the small files in Pocketbase is going to fill the server disk pretty fast (unless it's huge).  It does support separate storage in S3 (or it's ilk) which should solve this.  There is still a lot of data to manage in a SQLite DB, but it should be OK for some time.  
- Given that the Nuxt App is static files, it can be hosted with Pocketbase directly.  This is nice and makes it easier to host. 
- The next version of the daemon should have some more features around execution.
- AI?
- Additional language support?