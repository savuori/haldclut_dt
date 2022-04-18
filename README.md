# Utility used for creating HaldCLUT files for [Darktable](https://www.darktable.org/)

## Requirements

1. [Zig compiler](https://ziglang.org/) (tested on v0.9.1)
2. SDL2 -library
3. SDL2-image -library

## Building and running

Go to the directory where you cloned this repo and enter:
`zig build`

If compilation was successful you should be able to run the executable with:
`zig-out/bin/haldclut`


## Usage

At the moment this tool is not very user friendly. It expects to find a file called `images.txt` in the directory where you run it.
`images.txt` file should contain filenames on separate lines. Like:

```
DSCF1330.png
DSCF1332.png
...
```

The program then tries to find the listed files in **both** `source_images` **and** `target_images` -directories. `source_images` should
be photos ran through Darktable with default, minimal processing. No exposure adjustments (automatic or manual), no curves, no color adjustments. `target_images` ought to contain the same images but with the look you're trying to mimic, say, out of camera images with
certain film simulation.

When shooting images make sure the camera does not apply any kind of optical corrections (for example lens distortion). To ensure this you may want to shoot with an adapted/manual lens that the camera knows nothing about. 

For optimal results both images should be cropped to same size so that they're aligned perfectly. I'd recommend
also resizing both source and target images to something like 500x300 pixels to minimize the impact of other in-camera processing like noise reduction, sharpening etc. Save them as 8-bit PNGs. If you want to create a good LUT I'd advise shooting images with many different colors, skin tones, nothing in focus (to make them somewhat blurry) and exposures running from severely underexposed to severely overexposed. I usually want 80+ images for adequately accurate results.

After that preparation work run `zig-out/bin/haldclut` and hopefully you'll see it writing `lut.png`. Copy that to the directory you've configured Darktable to use for LUTs and check out the results.
