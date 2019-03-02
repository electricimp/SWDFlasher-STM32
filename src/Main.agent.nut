// MIT License

// Copyright 2019 Electric Imp

// SPDX-License-Identifier: MIT

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

@include "Logger.shared.nut"
@include "FWDownloader.agent.nut"


class SWDFlasherSTM32 {

    _swdp = null;
    _swma = null;
    _stm32 = null;

    _fwDownloader = null;

    _startTime = null;

    constructor() {
        const SWDFSTM32_EVENT_START_FLASHING = "start-flashing";
        const SWDFSTM32_EVENT_REQUEST_CHUNK  = "request-chunk";
        const SWDFSTM32_EVENT_RECEIVE_CHUNK  = "receive-chunk";
        const SWDFSTM32_EVENT_DONE_FLASHING  = "done-flashing";
        const SWDFSTM32_EVENT_ABORT_FLASHING = "abort-flashing";

        const SWDFSTM32_STATUS_OK = "OK";
        const SWDFSTM32_STATUS_ABORTED = "Aborted";
        const SWDFSTM32_STATUS_FAILED = "Failed";
    }

    function init() {
        device.on(SWDFSTM32_EVENT_REQUEST_CHUNK, _onRequestChunk.bindenv(this));
        device.on(SWDFSTM32_EVENT_DONE_FLASHING, _onDoneFlashing.bindenv(this));
    }

    function flashFirmware(fwDownloader) {
        _fwDownloader = fwDownloader;

        local onDone = function(err) {
            if (err) {
                logger.error("Failed to initialize downloader: " + err, LOG_SOURCE.APP);
                return;
            }

            _startTime = time();

            device.send(SWDFSTM32_EVENT_START_FLASHING, _fwDownloader.chunksNum());
        }.bindenv(this);

        _fwDownloader.init(onDone);
    }

    function _onRequestChunk(chunkNum) {
        logger.info("Chunk requested: " + chunkNum, LOG_SOURCE.APP);

        local onDone = function(err, data) {
            if (err) {
                logger.error("Failed to get next chunk: " + err, LOG_SOURCE.APP);
                device.send(SWDFSTM32_EVENT_ABORT_FLASHING);
                return;
            }
            device.send(SWDFSTM32_EVENT_RECEIVE_CHUNK, data);
        }.bindenv(this);

        _fwDownloader.getChunk(chunkNum, onDone);
    }

    function _onDoneFlashing(status) {
        logger.info("Flashing finished with status: " + status, LOG_SOURCE.APP);

        if (status == SWDFSTM32_STATUS_OK) {
            logger.info("Flashing took " + (time() - _startTime) + " sec", LOG_SOURCE.APP);
        }
    }
}


logger <- Logger(LOG_INFO_LEVEL);
flasher <- SWDFlasherSTM32();
flasher.init();

// TODO: replace with right links!
const IMAGE1_URL = "https://github.com/nobitlost/SWDFlasher-STM32/raw/develop/firmware/blinkSlow.bin";
const IMAGE2_URL = "https://github.com/nobitlost/SWDFlasher-STM32/raw/develop/firmware/blinkFast.bin";

const CREDENTIALS = "<username>:<password>";
local headers = {
    // "Authorization" : "Basic " + http.base64encode(CREDENTIALS)
};

fwDownloader <- FirmwareHTTPDownloader(IMAGE1_URL, headers);

flasher.flashFirmware(fwDownloader);
