class SWDFlasherSTM32 {

    _swdp = null;
    _swma = null;
    _stm32 = null;

    _chunkGenerator = null;

    constructor() {
        const SWDFSTM32_EVENT_START_FLASHING = "start-flashing";
        const SWDFSTM32_EVENT_REQUEST_CHUNK  = "request-chunk";
        const SWDFSTM32_EVENT_RECEIVE_CHUNK  = "receive-chunk";
        const SWDFSTM32_EVENT_DONE_FLASHING  = "done-flashing";
    }

    function init() {
        device.on(SWDFSTM32_EVENT_REQUEST_CHUNK, _onRequestChunk.bindenv(this));
        device.on(SWDFSTM32_EVENT_DONE_FLASHING, _onDoneFlashing.bindenv(this));
    }

    function sendImage(chunksNum, generator) {
        _chunkGenerator = generator();

        device.send(SWDFSTM32_EVENT_START_FLASHING, chunksNum);
    }

    function _onRequestChunk(chunkNum) {
        device.send(SWDFSTM32_EVENT_RECEIVE_CHUNK, {"num": chunkNum, "data": resume _chunkGenerator});
    }

    function _onDoneFlashing(status) {
        server.log("Flashing finished with status = " + status);
    }
}


flasher <- SWDFlasherSTM32();
flasher.init();


testFW1M <- [
    0x20002000,0x0000001d,0x00000061,0x00000063,
    0xbf00e001,0x28003801,0x4770d1fb,0xb5104b0c,
    0xf042699a,0x619a0214,0x22114b0a,0x4c09605a,
    0x69634809,0x7380f443,0xf7ff6163,0x6923ffe9,
    0xf4434805,0x61237380,0xffe2f7ff,0xbf00e7ef,
    0x40021000,0x40011000,0x000f4240,0x47702000,
    0x47704770
];

function image() {
    foreach (word in testFW1M) {
        yield [word];
    }
}

flasher.sendImage(testFW1M.len(), image);