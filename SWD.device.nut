const SWDP_ERROR_PARITY     = -1;
const SWDP_ERROR_TIMEOUT    = -2;
const SWDP_ERROR_ACK_FAIL   = -3;
const SWDP_ERROR_UNKNOWN    = -4;

const SWDP_ERR_INDEX = 0;
const SWDP_DATA_INDEX = 1;


class SWDebugPort {

    // TODO: turn off
    _debug = true;

    _clkPin = null;
    _dataPin = null;

    // write = 0
    // read = 1
    _rwState = 0;

    constructor(clkPin, dataPin) {

        const SWDP_ACK_OK = 1;
        const SWDP_ACK_WAIT = 2;
        const SWDP_ACK_FAIL = 4;

        _clkPin = clkPin;
        _dataPin = dataPin;
    }

    function connect() {
        _clkPin.configure(DIGITAL_OUT, 0);
        _dataPin.configure(DIGITAL_OUT, 0);

        _sendReset();
        _writeData(0xE79E, 16);
        _sendReset();
        _idle();

        return idcode()[SWDP_ERR_INDEX];
    }

    function resetLine() {
        _sendReset();
        _idle();
        local res = idcode();
        _idle();

        return res[SWDP_ERR_INDEX];
    }

    function readDP(addr) {
        return _read(0, addr);
    }

    function writeDP(addr, data) {
        return _write(0, addr, data);
    }

    function readAP(addr) {
        return _read(1, addr);
    }

    function writeAP(addr, data) {
        return _write(1, addr, data);
    }

    function idcode() {
        return readDP(0);
    }

    function abort() {
        // TODO: implement
    }

    function control(value) {
        // TODO: finish this method
        writeDP(1, value);
    }

    function status() {
        return readDP(1);
    }

    function select(apsel, apbank) {
        local data = (apsel & 0xFF) << 24;
        data = data | ((apbank & 0x0F) << 4);
        return writeDP(2, data);
    }

    function rdbuff() {
        return readDP(3);
    }

    function setDebug(value) {
        _debug = value;
    }

    function _read(ap, addr) {
        // Write header
        // Turnaround
        // Ack
        // Read data
        // Read parity
        // Turnaround

        _log(format("Read request: ap = 0x%01x addr = 0x%01x", ap, addr));

        local header = _createHeader(ap, 1, addr);
        _log(format("Header = 0x%02x", header));
        _writeHeader(header);

        _trnToRead();

        local ack = _ack();
        _log(format("ACK = 0x%01x", ack));

        if (ack == SWDP_ACK_WAIT) {
            // TODO
            _trnToWrite();
            return [SWDP_ERROR_TIMEOUT, null];
        } else if (ack == SWDP_ACK_FAIL) {
            // TODO
            _trnToWrite();
            return [SWDP_ERROR_ACK_FAIL, null];
        }

        local data = _readBits(32);
        _log(format("Data = 0x%08x", data));

        local parityRead = _readBits(1);
        _log(format("Parity = 0x%01x", parityRead));

        _trnToWrite();

        // Check parity
        if (parityRead != _parity(data)) {
            return [SWDP_ERROR_PARITY, null];
        }

        return [0, data];
    }

    // data is a word (4B)
    function _write(ap, addr, data, ignoreAck = false) {
        // Write header
        // Turnaround
        // Ack
        // Turnaround
        // Write data
        // Write parity

        _log(format("Write request: ap = 0x%01x addr = 0x%01x data = 0x%08x", ap, addr, data));

        local header = _createHeader(ap, 0, addr);
        _log(format("Header = 0x%02x", header));
        _writeHeader(header);

        _trnToRead();

        local ack = _ack();
        _log(format("ACK = 0x%01x", ack));

        _trnToWrite();

        if (!ignoreAck && (ack == SWDP_ACK_WAIT)) {
            // TODO
            return SWDP_ERROR_TIMEOUT;
        } else if (!ignoreAck && (ack == SWDP_ACK_FAIL)) {
            // TODO
            return SWDP_ERROR_ACK_FAIL;
        }

        _writeData(data, 32);
        _writeData(_parity(data), 1);

        _idle();

        return 0;
    }

    function _createHeader(ap, rw, addr) {
        local parity = ap + rw + (addr >>> 1) + (addr & 1);
        parity = parity & 1;

        // 0x81 = 0b10000001
        local header = 0x81;
        header = header | (ap << 6);
        header = header | (rw << 5);
        header = header | ((addr & 1) << 4);
        header = header | ((addr & 2) << 2);
        header = header | (parity << 2);

        return header;
    }

    function _writeHeader(header) {
        for (local i = 0; i < 8; i++) {
            _dataPin.write(header & 128);
            _clkPin.write(1);
            _clkPin.write(0);
            header = header << 1;
        }
    }

    function _writeData(word, bitsNum = 32) {
        for (local i = 0; i < bitsNum; i++) {
            _dataPin.write(word & 1);
            _clkPin.write(1);
            _clkPin.write(0);
            word = word >>> 1;
        }
    }

    function _readBits(bitsNum = 32) {
        local word = 0;
        for (local i = 0; i < bitsNum; i++) {
            word = word | (_dataPin.read() << i);
            _clkPin.write(1);
            _clkPin.write(0);
        }
        return word;
    }

    function _ack() {
        // 100 - OK
        // 010 - WAIT
        // 001 - FAIL
        return _readBits(3);
    }

    function _trnToRead() {
        _dataPin.configure(DIGITAL_IN_PULLUP);
        _clkPin.write(1);
        _clkPin.write(0);
        _rwState = 1;
    }

    function _trnToWrite() {
        _clkPin.write(1);
        _clkPin.write(0);
        _dataPin.configure(DIGITAL_OUT, 0);
        _rwState = 0;
    }

    function _sendReset() {
        _dataPin.write(1);
        for (local i = 0; i < 56; i++) {
            _clkPin.write(1);
            _clkPin.write(0);
        }
        _dataPin.write(0);
    }

    function _idle() {
        _writeData(0, 8);
    }

    function _readStickyBits() {

    }

    function _parity(word) {
        local parity = 0;
        for (parity = 0; word != 0; parity = parity ^ 1) {
            word = word & (word - 1);
        }
        return parity;
    }

    function _log(text) {
        _debug && server.log(text);
    }

    function _logError(text) {
        server.error(text);
    }
}


const SWMA_SIZE_WORD = 0x00000002;
const SWMA_SIZE_HALFWORD = 0x00000001;

class SWMemAP {

    // TODO: turn off
    _debug = true;

    _swdp = null;

    constructor(swDebugPort) {
        _swdp = swDebugPort;
    }

    function init() {
        _swdp.control((1 << 30) | (1 << 28) | (1 << 26));
        if ((_swdp.status()[SWDP_DATA_INDEX] >>> 24) != 0xF4) {
            throw "The device is not ready";
        }
        if (idcode()[SWDP_DATA_INDEX] != 0x14770011) {
            throw "Unknown MEM-AP IDCODE";
        }
        _swdp.select(0, 0);
        // _setCSW(1, 2);
    }

    function idcode() {
        _swdp.select(0, 0xF);
        _swdp.readAP(3);
        return _swdp.rdbuff();
    }

    function readWord(addr) {
        // TODO: check the AP selected
        // _swdp.writeAP(1, addr);
        _memAccessSetup(addr);
        _swdp.readAP(3);
        return _swdp.rdbuff();
    }

    function writeWord(addr, data) {
        // TODO: check the AP selected
        // _swdp.writeAP(1, addr);
        _memAccessSetup(addr);
        return _swdp.writeAP(3, data);
    }

    function writeHalfs(addr, data) {
        // _setCSW(2, 1);
        _memAccessSetup(addr, SWMA_SIZE_HALFWORD, true);
        // _swdp.writeAP(1, addr);
        foreach (val in data) {
            // imp.sleep(0.001);
            _swdp.writeAP(3, val);
        }
        // _setCSW(1, 2);
    }

    function _setCSW(addrInc, size) {
        _swdp.readAP(0);
        local csw = _swdp.rdbuff()[SWDP_DATA_INDEX] & 0xFFFFFF00;
        _swdp.writeAP(0, csw + (addrInc << 4) + size);
    }

    function _memAccessSetup(addr, size = SWMA_SIZE_WORD, autoIncrement = false) {
        // Docs: CSW register - http://infocenter.arm.com/help/topic/com.arm.doc.ddi0337h/BABGBEEC.html#BABBCECJ
        // Docs: Automatic address increment - p.C2-153 https://static.docs.arm.com/ihi0031/d/debug_interface_v5_2_architecture_specification_IHI0031D.pdf
        // Docs: access size for memory accesses - p.C2-156 https://static.docs.arm.com/ihi0031/d/debug_interface_v5_2_architecture_specification_IHI0031D.pdf

        // Transfer Address Register
        const SWMA_TAR_OFFSET = 0x1;
        // Control/Status Word Register
        const SWMA_CSWR_OFFSET = 0x0;
        const SWMA_AUTO_INCR_SINGLE = 0x00000010;
        const SWMA_AUTO_INCR_PACKED = 0x00000020;

        _swdp.readAP(SWMA_CSWR_OFFSET);
        local csw = _swdp.rdbuff()[SWDP_DATA_INDEX] & 0xFFFFFF00;

        switch (size) {
            case SWMA_SIZE_WORD:
                if (autoIncrement) {
                    csw = csw | SWMA_AUTO_INCR_SINGLE;
                }
                break;
            case SWMA_SIZE_HALFWORD:
                if (autoIncrement) {
                    csw = csw | SWMA_AUTO_INCR_PACKED;
                }
                break;
            default:
                throw "Unknown memory access size";
                break;
        }
        // TODO: Implement the other access sizes (?)

        csw = csw | size;

        // Write the new value into the CSW register
        _swdp.writeAP(SWMA_CSWR_OFFSET, csw);
        // Write the address into the TAR register
        _swdp.writeAP(SWMA_TAR_OFFSET, addr);
    }

}
