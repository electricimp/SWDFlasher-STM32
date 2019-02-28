@include "Logger.shared.nut"
@include "FWDownloader.agent.nut"


class SWDFlasherSTM32 {

    _swdp = null;
    _swma = null;
    _stm32 = null;

    _fwDownloader = null;

    constructor() {
        const SWDFSTM32_EVENT_START_FLASHING = "start-flashing";
        const SWDFSTM32_EVENT_REQUEST_CHUNK  = "request-chunk";
        const SWDFSTM32_EVENT_RECEIVE_CHUNK  = "receive-chunk";
        const SWDFSTM32_EVENT_DONE_FLASHING  = "done-flashing";
        const SWDFSTM32_EVENT_ABORT_FLASHING = "abort-flashing";
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
    }
}


logger <- Logger(LOG_INFO_LEVEL);
flasher <- SWDFlasherSTM32();
flasher.init();

const IMAGE_URL = "https://github.com/willdonnelly/pirate-swd/raw/master/stm32-firmwares/blink1M.bin";
const CREDENTIALS = "<username>:<password>"
local headers = {
    // "Authorization" : "Basic " + http.base64encode(CREDENTIALS)
};
fwDownloader <- FirmwareHTTPDownloader(IMAGE_URL, headers);

flasher.flashFirmware(fwDownloader);
