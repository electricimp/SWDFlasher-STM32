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
@include __PATH__ + "/SWDebugPort.device.nut"
@include __PATH__ + "/SWMemAP.device.nut"
@include __PATH__ + "/SWDSTM32.device.nut"


SWDFSTM32_SWCLK_PIN <- hardware.pinC;
SWDFSTM32_SWDIO_PIN <- hardware.pinD;


class SWDFlasherSTM32 {

    _swdp = null;
    _swma = null;
    _stm32 = null;

    _chunksToFlash = null;
    _expectedChunk = null;

    constructor(swdPinClk, swdPinData) {
        const SWDFSTM32_EVENT_START_FLASHING = "start-flashing";
        const SWDFSTM32_EVENT_REQUEST_CHUNK  = "request-chunk";
        const SWDFSTM32_EVENT_RECEIVE_CHUNK  = "receive-chunk";
        const SWDFSTM32_EVENT_DONE_FLASHING  = "done-flashing";
        const SWDFSTM32_EVENT_ABORT_FLASHING = "abort-flashing";

        const SWDFSTM32_STATUS_OK = "OK";
        const SWDFSTM32_STATUS_ABORTED = "Aborted";
        const SWDFSTM32_STATUS_FAILED = "Failed";

        _swdp = SWDebugPort(swdPinClk, swdPinData);
        _swma = SWMemAP(_swdp);
        _stm32 = SWDSTM32(_swdp, _swma);
    }

    function init() {
        agent.on(SWDFSTM32_EVENT_START_FLASHING, _onStartFlashing.bindenv(this));
        agent.on(SWDFSTM32_EVENT_RECEIVE_CHUNK, _onReceiveChunk.bindenv(this));
        agent.on(SWDFSTM32_EVENT_ABORT_FLASHING, _onAbortFlashing.bindenv(this));
    }

    function _onStartFlashing(chunksNum) {
        if (_expectedChunk != null) {
            logger.error("Got a request to start flashing but it is already in progress", LOG_SOURCE.APP);
            return;
        }

        logger.info("Starting flashing. Chunks to flash: " + chunksNum, LOG_SOURCE.APP);

        _chunksToFlash = chunksNum;
        _expectedChunk = 0;

        local err = 0;
        if (err = _stm32.connect()           ||
                  _stm32.halt()              ||
                  _stm32.enableHaltOnReset() ||
                  _stm32.sysReset()          ||
                  _stm32.flashUnlock()       ||
                  _stm32.flashErase()        ||
                  _stm32.beginProgramming()) {

            logger.error("An error occured. Flashing failed: " + err, LOG_SOURCE.APP);
            _onDoneFlashing(SWDFSTM32_STATUS_FAILED);
            return;
        }

        agent.send(SWDFSTM32_EVENT_REQUEST_CHUNK, 0);
    }

    function _onReceiveChunk(chunk) {
        logger.info("Chunk received", LOG_SOURCE.APP);

        if (_expectedChunk == null) {
            logger.error("Flashing is not in progress now", LOG_SOURCE.APP);
            return;
        }

        local err = _stm32.program(chunk);
        if (err) {
            logger.error("An error occured during writing the chunk. Flashing failed: " + err, LOG_SOURCE.APP);
            _onDoneFlashing(SWDFSTM32_STATUS_FAILED);
            return;
        }

        _expectedChunk++;

        if (_expectedChunk == _chunksToFlash) {
            logger.info("All chunks were written", LOG_SOURCE.APP);
            _onDoneFlashing(SWDFSTM32_STATUS_OK);
            return;
        }

        agent.send(SWDFSTM32_EVENT_REQUEST_CHUNK, _expectedChunk);
    }

    function _onAbortFlashing(_) {
        if (_expectedChunk == null) {
            logger.error("Got a request to abort flashing but it is not in progress", LOG_SOURCE.APP);
            return;
        }

        logger.info("Abort flashing request received!", LOG_SOURCE.APP);
        _onDoneFlashing(SWDFSTM32_STATUS_ABORTED);
    }

    function _onDoneFlashing(status) {
        _chunksToFlash = null;
        _expectedChunk = null;

        if (status == SWDFSTM32_STATUS_OK) {
            logger.info("Finishing the flashing...", LOG_SOURCE.APP);

            local err = _stm32.endProgramming() ||
                        _stm32.disableHaltOnReset() ||
                        _stm32.sysReset();
            if (err) {

                logger.error("An error occured. Flashing failed: " + err, LOG_SOURCE.APP);

                status = SWDFSTM32_STATUS_FAILED;
            } else {
                logger.info("Flashing was finished successfully!", LOG_SOURCE.APP);
            }
        } else {
            _stm32.endProgramming();
        }

        agent.send(SWDFSTM32_EVENT_DONE_FLASHING, status);
    }
}

// Use this logger configuration during debugging
// logger <- Logger(LOG_DEBUG_LEVEL, LOG_SOURCE.ANY);
logger <- Logger(LOG_INFO_LEVEL, LOG_SOURCE.APP | LOG_SOURCE.SWDSTM32);

flasher <- SWDFlasherSTM32(SWDFSTM32_SWCLK_PIN, SWDFSTM32_SWDIO_PIN);
flasher.init();
