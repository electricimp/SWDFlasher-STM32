# SWDFlasher-STM32 #

This is an example application for flashing the STM32F100 MCU over-the-air (OTA) via imp module. 
It downloads a firmware image via HTTPs and uses the SWD protocol to program the MCU.

## Hardware ##

- [imp004m Breakout Board](https://store.electricimp.com/products/imp004m-breakout-board?variant=33852062354) or [imp003 Breakout Board](https://store.electricimp.com/products/imp003-breakout-board?variant=31162918482)
- [STM32VLDISCOVERY](https://www.st.com/en/evaluation-tools/stm32vldiscovery.html)

**Note**: Other hardware may be used but haven't been tested. The implementation is general for any STM32F10xxx MCU but tested only with STM32F100RBT6B ( which is installed on the STM32VLDISCOVERY board).

## Wiring ##

You will need 3 wires:
1) GND (of imp) <&mdash;> GND (of STM32 MCU)
2) PinC (of imp) <&mdash;> SWCLK (of STM32 MCU)
3) PinD (of imp) <&mdash;> SWDIO (of STM32 MCU)

**Note**: Generally speaking, any GPIO pins can be used on the imp's side. But you will need to specify your pins in the code (at the bottom of [Main.device.nut](./src/Main.device.nut)).

For STM32VLDISCOVERY: remove jumpers from CN3 connector of your MCU and wire it with the imp as shown at the following picture

![STM32VLDISCOVERY Wiring](./imgs/Wiring.png)

## Setup ##

### Firmware image ###

The example requires an HTTP link to a firmware binary image.

The link should be added into the code in the [Main.agent.nut](./src/Main.agent.nut) file (almost at the end of the file):
```squirrel
fwDownloader <- FirmwareHTTPDownloader(<YOUR LINK>, headers);
```

There are 2 sample images in the [firmware folder](./firmware/). You can use them to try the example. They are also made for STM32VLDISCOVERY board. \
To use one of the sample images just insert a constant (`IMAGE1_URL` or `IMAGE2_URL`) instead of your link:
```squirrel
const IMAGE1_URL = "https://github.com/electricimp/SWDFlasher-STM32/raw/master/firmware/blinkSlow.bin";
const IMAGE2_URL = "https://github.com/electricimp/SWDFlasher-STM32/raw/master/firmware/blinkFast.bin";
fwDownloader <- FirmwareHTTPDownloader(IMAGE1_URL, headers);
```
The constants `IMAGE1_URL` and `IMAGE2_URL` contain direct links to the sample firmware in the [firmware folder](./firmware/).
The sample firmware blinks with a blue LED integrated to the STM32VLDISCOVERY board.

### Basic HTTP Authentication ###

If you need to use Basic HTTP Authentication for downloading your firmware, just add your credentials to the headers:
```squirrel
const CREDENTIALS = "<username>:<password>";
local headers = {
    "Authorization" : "Basic " + http.base64encode(CREDENTIALS)
};
fwDownloader <- FirmwareHTTPDownloader(<YOUR LINK>, headers);
```

## Limitations ##

The example:
- Has been tested only manually with STM32VLDISCOVERY (STM32F100RBT6B)
- Supports firmware downloading only via HTTPs (and authentication is only Basic)
- Supports only Binary images of firmware
