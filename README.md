# ScreenshotImporter
for macOS.

ScreenshotImporter is a command line tool to import your screenshots to Photos.app

-- -- -- 

## Installation
1. clone this repo and run the project.
2. create a screenshot.
3. Enjoy.

## Automatic tasks
- [x] create a hidden folder `~/Desktop/Screenshots`
- [x] install the ScreenshotImporter binary in `~/Desktop/screenshots`
- [x] set the output location of your screenshots to `~/Desktop/Screenshots` using `defaults write com.apple.screencapture location ~/Desktop/Screenshots` 
- [x] We'll install a launchDeamon to check for new screenshots (This produces a terminal window which will disappear after running, if someone knows a slolution, please tell :))
