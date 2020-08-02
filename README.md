# ScreenshotImporter
for macOS.

ScreenshotImporter is a command line tool to import your screenshots to Photos.app

-- -- -- 
<center>
### ⚠️ Work in progress.
Unstable version.

The project *_should_* work, but is at this moment _untested_.
</center>
-- -- -- 

## Installation
1. go to releases and download the latest release  
(optional: clone this repo and build the project)
2. create `~/Desktop/Screenshots`
3. install the ScreenshotImporter binary in `~/Desktop/screenshots` (will prompt for automatic placement in future)
4. set the output location of your screenshots to `~/Desktop/Screenshots` using `defaults write com.apple.screencapture location ~/Desktop/Screenshots` 
5. We'll install a launchDeamon to check for new screenshots
6. Hide the folder `~/Desktop/Screenshots` using `chflags hidden ~/Desktop/Screenshots` (will be a prompt)

Steps 2 to 6, will be automated for you.
