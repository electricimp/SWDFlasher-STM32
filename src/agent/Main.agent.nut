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

@include __PATH__ + "/../shared/Logger.shared.nut"
@include __PATH__ + "/FWDownloader.agent.nut"


class SWDFlasherSTM32 {

    _swdp = null;
    _swma = null;
    _stm32 = null;

    _fwDownloader = null;

    _startTime = null;

    _dispatchTable = null;
    _deviceRespondTimer = null;

    constructor(fwDownloader = null) {
        const SWDFSTM32_EVENT_START_FLASHING = "start-flashing";
        const SWDFSTM32_EVENT_REQUEST_CHUNK  = "request-chunk";
        const SWDFSTM32_EVENT_RECEIVE_CHUNK  = "receive-chunk";
        const SWDFSTM32_EVENT_DONE_FLASHING  = "done-flashing";
        const SWDFSTM32_EVENT_ABORT_FLASHING = "abort-flashing";

        const SWDFSTM32_STATUS_OK = "OK";
        const SWDFSTM32_STATUS_ABORTED = "Aborted";
        const SWDFSTM32_STATUS_FAILED = "Failed";

        // Sec
        const SWDFSTM32_TIMEOUT = 60;

        _fwDownloader = fwDownloader;

        _dispatchTable = {
            "/flash" : _flashRequest.bindenv(this)
        };
    }

    function init() {
        device.on(SWDFSTM32_EVENT_REQUEST_CHUNK, _onRequestChunk.bindenv(this));
        device.on(SWDFSTM32_EVENT_DONE_FLASHING, _onDoneFlashing.bindenv(this));

        http.onrequest(_dispatchRequest.bindenv(this));
    }

    function flashFirmware(fwDownloader = null) {
        if (fwDownloader != null) {
            _fwDownloader = fwDownloader;
        }

        if (_fwDownloader == null) {
            throw "Firmware downloader is not set";
        }

        local onDone = function(err) {
            if (err) {
                logger.error("Failed to initialize downloader: " + err, LOG_SOURCE.APP);
                return;
            }

            _startTime = time();

            device.send(SWDFSTM32_EVENT_START_FLASHING, _fwDownloader.chunksNum());
            _resetRespondTimer();
        }.bindenv(this);

        _fwDownloader.init(onDone);
    }

    function isFlashing() {
        return _startTime != null;
    }

    function _onRequestChunk(chunkNum) {
        if (!isFlashing()) {
            logger.error("Got a request to send a chunk but flashing is not in progress", LOG_SOURCE.APP);
            device.send(SWDFSTM32_EVENT_ABORT_FLASHING, null);
            return;
        }

        logger.info("Chunk requested: " + chunkNum, LOG_SOURCE.APP);

        _resetRespondTimer();

        local onDone = function(err, data) {
            if (err) {
                logger.error("Failed to get next chunk: " + err, LOG_SOURCE.APP);
                device.send(SWDFSTM32_EVENT_ABORT_FLASHING, null);
                return;
            }
            device.send(SWDFSTM32_EVENT_RECEIVE_CHUNK, data);
        }.bindenv(this);

        _fwDownloader.getChunk(chunkNum, onDone);
    }

    function _onDoneFlashing(status) {
        if (!isFlashing()) {
            logger.error("Got a request to done flashing but it is not in progress", LOG_SOURCE.APP);
            return;
        }

        logger.info("Flashing finished with status: " + status, LOG_SOURCE.APP);

        if (status == SWDFSTM32_STATUS_OK) {
            logger.info("Flashing took " + (time() - _startTime) + " sec", LOG_SOURCE.APP);
        }

        _startTime = null;
        _resetRespondTimer();
    }

    function _resetRespondTimer() {
        _deviceRespondTimer && imp.cancelwakeup(_deviceRespondTimer);

        if (isFlashing()) {
            _deviceRespondTimer = imp.wakeup(SWDFSTM32_TIMEOUT, _deviceNotResponding.bindenv(this));
        }
    }

    function _deviceNotResponding() {
        logger.error("Device doesn't respond", LOG_SOURCE.APP);

        _onDoneFlashing(SWDFSTM32_STATUS_FAILED);
    }

    function _flashRequest(request, response) {
        // Handler for "/flash" endpoint

        local responseCode = 200;
        local responseBody = {"message": "OK"};

        switch (request.method) {
            case "GET":
                if (_fwDownloader == null) {
                    responseCode = 500;
                    responseBody.message = "Default firmware downloader is not set";
                    break;
                }
                if (isFlashing()) {
                    responseBody.message = "Flashing is already in progress";
                    break;
                }
                flashFirmware();
                break;
            default:
                responseCode = 400;
                responseBody.message = "Unknown operation";
        };

        response.header("Content-Type", "application/json");
        response.send(responseCode, http.jsonencode(responseBody));
    }

    function _dispatchRequest(request, response) {
        // This is a simple HTTP requests dispatcher

        foreach (urlPattern, handler in _dispatchTable) {
            if (request.path.find(urlPattern) == 0) {
                handler(request, response);
                return;
            };
        }

        // 404 handler
        response.send(404, "No such endpoint.");
    }
}


logger <- Logger(LOG_INFO_LEVEL);


const IMAGE_URL = "<link to your firmware image>";

// If you want to use Basic HTTP Authentication, enter your
// credentials here in "<username>:<password>" format
// Otherwise leave the constant empty
const CREDENTIALS = "";
local headers = {};
if (CREDENTIALS.len() > 0) {
    headers["Authorization"] = "Basic " + http.base64encode(CREDENTIALS);
}

fwDownloader <- FirmwareHTTPDownloader(IMAGE_URL, headers);

flasher <- SWDFlasherSTM32(fwDownloader);
flasher.init();
