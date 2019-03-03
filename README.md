# SWDFlasher-STM32 #

This is an example application for flashing the STM32F100 MCU over-the-air (OTA) via imp module. 
It downloads a firmware image via HTTPs and uses the SWD protocol to program the MCU. \
The application contains both agent's and device's parts.

## Hardware ##

- [imp004m Breakout Board](https://store.electricimp.com/products/imp004m-breakout-board?variant=33852062354) or [imp003 Breakout Board](https://store.electricimp.com/products/imp003-breakout-board?variant=31162918482)
- [STM32VLDISCOVERY](https://www.st.com/en/evaluation-tools/stm32vldiscovery.html)

**Note**: Other hardware may be used but haven't been tested. The implementation is general for any STM32F10xxx MCU but tested only with STM32F100RBT6B (which is installed on the STM32VLDISCOVERY board).

## Wiring ##

You will need 3 wires:
1) GND (of imp) <&mdash;> GND (of STM32 MCU)
2) PinC (of imp) <&mdash;> SWCLK (of STM32 MCU)
3) PinD (of imp) <&mdash;> SWDIO (of STM32 MCU)

**Note**: Generally speaking, any GPIO pins can be used on the imp's side. But you will need to specify your pins in the code (`SWDFSTM32_SWCLK_PIN` and `SWDFSTM32_SWDIO_PIN` constants in [Main.device.nut](./src/device/Main.device.nut)).

For STM32VLDISCOVERY: remove jumpers from CN3 connector of your MCU and wire it with the imp as shown at the following picture

![STM32VLDISCOVERY Wiring](./imgs/Wiring.png)

## Setup ##

### Firmware image ###

The example requires an HTTP link to a firmware **binary** image.

The link should be added into the code in the [Main.agent.nut](./src/agent/Main.agent.nut) file (almost at the end of the file):
```squirrel
const IMAGE_URL = "<link to your firmware image>";
```

There are 2 sample images in the [firmware folder](./firmware/). You can use them to try the example. They are also made for STM32VLDISCOVERY board. \
To use one of the sample images you need to obtain a direct link:
1. Copy to the clipboard one of the following links: [blinkFast.bin](./firmware/blinkFast.bin?raw=true) or [blinkSlow.bin](./firmware/blinkSlow.bin?raw=true)
1. Paste the link into the code as a value of the `IMAGE_URL` constant

The sample firmware blinks with a blue LED integrated to the STM32VLDISCOVERY board. These two firmwares differ in the frequency of blinking.

### Basic HTTP Authentication ###

If you need to use Basic HTTP Authentication for downloading your firmware, just add your credentials to the headers:
```squirrel
const CREDENTIALS = "<username>:<password>";
local headers = {
    "Authorization" : "Basic " + http.base64encode(CREDENTIALS)
};
fwDownloader <- FirmwareHTTPDownloader(<YOUR LINK>, headers);
```

### How To Run ###

You have two options of how to build and run the application:
1. [Manually](#build-and-run-manually)
1. [Using Sublime Plug-In](#build-and-run-using-sublime-plug-in)

Once you run the application, please see the [Start Flashing](#start-flashing) section.

#### Build And Run Manually ####

Project's source code has the following structure:
- ["src/agent" folder](./src/agent) - agent code
- ["src/device" folder](./src/device) - device code
- ["src/shared" folder](./src/shared) - shared code (for both agent and device)

To build the project use [Builder](https://github.com/electricimp/Builder). Just call it for the [Main.agent.nut](./src/agent/Main.agent.nut) and [Main.device.nut](./src/device/Main.device.nut) files.
For example: run these commands from the "src/" directory `pleasebuild agent/Main.agent.nut > agent.nut` and `pleasebuild device/Main.device.nut > device.nut` and you will get two new files: `agent.nut` and `device.nut`. Then you can copy the content of these files to the [Electric Imp's IDE](https://impcentral.electricimp.com/ide/) and run the application.

#### Build And Run Using Sublime Plug-In ####

You can use this option instead of manual building and running the application. \
This project has been written using [Sublime Plug-in](https://github.com/electricimp/ElectricImp-Sublime). All configuration settings and pre-processed files have been excluded.
1. Follow the instructions [here](https://github.com/electricimp/ElectricImp-Sublime#installation) to install the plug-in and create a project.
2. Replace the `src` folder in your newly created project with the `src` folder found in this repository
3. Update `settings/electric-imp.settings` "device-file" and "agent-file" to the following (on Windows use `\\` instead of `/`):
```
    "device-file": "src/device/Main.device.nut",
    "agent-file": "src/agent/Main.agent.nut"
```
4. [Build and run the application](https://github.com/electricimp/ElectricImp-Sublime#building-and-running)

#### Start Flashing ####

If the application is running, you should make an HTTP GET-request to the `/flash` endpoint of agent to start flashing. \
You can just click on the agent's URL in the [Electric Imp's IDE](https://impcentral.electricimp.com/ide/), append `/flash` to the URL and press Enter.

This message in the logs states successful flashing: `Flashing finished with status: OK`. \
Be prepared that the flashing process may take a while. During the process you should see messages like `Chunk requested`/`Chunk received`. \
Speed of flashing is about 450B/s (has been measured during the testing with STM32VLDISCOVERY).

## How To Make A Binary Image ##

There is a number of different formats of firmware images. This example supports **only binary** format. If you have an image in a different format, you need to convert it to binary first. \
This can be done using the ["objcopy" (or "arm-none-eabi-objcopy")](https://linux.die.net/man/1/objcopy) utility from the [
GNU Arm Embedded Toolchain](https://developer.arm.com/open-source/gnu-toolchain/gnu-rm). \
Example command: `arm-none-eabi-objcopy -I ihex your_firmware_image.hex -O binary your_firmware_image.bin`. \
This command converts an image from Intel HEX format to binary.

## Limitations ##

The example:
- Has been tested only manually with STM32VLDISCOVERY (STM32F100RBT6B)
- Supports firmware downloading only via HTTPs (and authentication is only Basic)
- Supports only Binary images of firmware

# License #

Code licensed under the [MIT License](./LICENSE).
