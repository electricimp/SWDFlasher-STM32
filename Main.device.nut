@include "SWD.device.nut"
@include "SWDSTM32.device.nut"

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

        const SWDFSTM32_STATUS_OK = "OK";
        const SWDFSTM32_STATUS_ABORTED = "Aborted";


        _swdp = SWDebugPort(swdPinClk, swdPinData);
        _swma = SWMemAP(_swdp);
        _stm32 = SWDSTM32(_swdp, _swma);
    }

    function init() {
        agent.on(SWDFSTM32_EVENT_START_FLASHING, _onStartFlashing.bindenv(this));
        agent.on(SWDFSTM32_EVENT_RECEIVE_CHUNK, _onReceiveChunk.bindenv(this));
    }

    function abortFlashing() {
        _onDoneFlashing(SWDFSTM32_STATUS_ABORTED);
    }

    function _onStartFlashing(chunksNum) {
        _chunksToFlash = chunksNum;
        _expectedChunk = 0;


        _swdp.connect();
        _swma.init();

        _stm32.halt();
        _stm32.flashUnlock();
        _stm32.flashErase();
        _stm32.flashProgram();

        // _stm32._wait();
        _swma._setCSW(2, 1);
        _swdp.writeRequest(1, 1, 0x08000000);

        agent.send(SWDFSTM32_EVENT_REQUEST_CHUNK, 0);
    }

    function _onReceiveChunk(chunk) {
        if (_expectedChunk == null) {
            return;
        }
        if (!("num" in chunk && "data" in chunk && _expectedChunk == chunk.num)) {
            server.error("Invalid chunk received!");
            abortFlashing();
            return;
        }

        _writeChunk(chunk.data);
        _expectedChunk++;
        if (_expectedChunk == _chunksToFlash) {
            _onDoneFlashing(SWDFSTM32_STATUS_OK);
        }
        agent.send(SWDFSTM32_EVENT_REQUEST_CHUNK, _expectedChunk);
    }

    function _writeChunk(data) {
        foreach (word in data) {
            _swdp.writeRequest(1, 3, word);
            imp.sleep(0.001);
            // _stm32._wait();
            // server.log(format("Word = 0x%08x", word));
        }
    }

    function _onDoneFlashing(status) {
        _chunksToFlash = null;
        _expectedChunk = null;

        _swma._setCSW(1, 2);
        _stm32.flashProgramEnd();
        _stm32.sysReset();

        agent.send(SWDFSTM32_EVENT_DONE_FLASHING, status);
    }
}

flasher <- SWDFlasherSTM32(hardware.pinC, hardware.pinD);
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

testFW100k <- [
    0x20002000,0x0000001d,0x00000061,0x00000063,
    0xbf00e001,0x28003801,0x4770d1fb,0xb5104b0c,
    0xf042699a,0x619a0214,0x22114b0a,0x4c09605a,
    0x69634809,0x7380f443,0xf7ff6163,0x6923ffe9,
    0xf4434805,0x61237380,0xffe2f7ff,0xbf00e7ef,
    0x40021000,0x40011000,0x000186a0,0x47702000,
    0x47704770
];

// swdp <- SWDebugPort(hardware.pinC, hardware.pinD);
// swma <- SWMemAP(swdp);
// stm32 <- SWDSTM32(swdp, swma);

// swdp.connect();
// swma.init();

// swma.readWord(0xE0042000);
// return;

// stm32.halt();
// stm32.flashUnlock();
// stm32.flashErase();
// stm32.flashProgram();
// swma.writeHalfs(0x08000000, testFW1M);
// stm32.flashProgramEnd();
// stm32.sysReset();
