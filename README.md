# SWDFlasher-STM32 #

This is an example application for flashing the STM32F100 MCU over-the-air (OTA) via imp module. 
It downloads a firmware image via HTTPs and uses the SWD protocol to program MCU.

## Hardware ##

- [imp004m Breakout Board](https://store.electricimp.com/products/imp004m-breakout-board?variant=33852062354) or [imp003 Breakout Board](https://store.electricimp.com/products/imp003-breakout-board?variant=31162918482)
- [STM32VLDISCOVERY](https://www.st.com/en/evaluation-tools/stm32vldiscovery.html)

**Note**: Other hardware may be used but haven't been tested. The implementation is general for any STM32F10xxx MCU but but tested only with STM32F100RBT6B (installed on the STM32VLDISCOVERY board).

## Wiring ##

You will need 3 wires:
1) GND (of imp) <&mdash;> GND (of STM32 MCU)
2) PinC (of imp) <&mdash;> SWCLK (of STM32 MCU)
3) PinD (of imp) <&mdash;> SWDIO (of STM32 MCU)

**Note**: Generally speaking, any GPIO pins can be used on the imp's side. But you will need to specify your pins in the code (TODO).

For STM32VLDISCOVERY: remove jumpers from CN3 connector of your MCU and wire it with the imp as shown at the following picture

![STM32VLDISCOVERY Wiring](./imgs/Wiring.png)

## Setup ##

### Firmware image ###

The example requires an HTTP link to a firmware binary image.

The link should be added into the code:
```squirrel
fwDownloader <- FirmwareHTTPDownloader(<YOUR LINK>, headers);
```

There are 2 sample images in the [firmware folder](./firmware/). You can use them to try the example. They are also made for STM32VLDISCOVERY board. \
To use one of the sample images just insert a constant (`IMAGE1_URL` or `IMAGE2_URL`) instead of your link:
```squirrel
fwDownloader <- FirmwareHTTPDownloader(IMAGE1_URL, headers);
```

## Basic HTTP Authentication ###
