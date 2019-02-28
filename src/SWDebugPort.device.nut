const SWDP_ERROR_PARITY     = -1;
const SWDP_ERROR_TIMEOUT    = -2;
const SWDP_ERROR_ACK_FAIL   = -3;
const SWDP_ERROR_ACK_INVAL  = -4;

// Docs: ARM IHI0031D (https://static.docs.arm.com/ihi0031/d/debug_interface_v5_2_architecture_specification_IHI0031D.pdf)

enum SWDP_REGISTER {
    // Read only
    // DPIDR provides information about the Debug Port.
    DPIDR       = 0x0,

    // Write only
    // The ABORT register forces an AP transaction abort.
    // In DPv1 and DPv2 only, the ABORT register has additional fields that clear error and
    // sticky flag conditions.
    // In DPv0, these fields are reserved, SBZ (should be zero).
    ABORT       = 0x0,

    // Read/Write. NOTE: To access the CTRL/STAT register DPBANKSEL of the SELECT register must be 0x0
    // The Control/Status register provides control of the DP and status information about the DP.
    CTRL_STAT   = 0x4,

    // Read only
    // The RESEND register enables the read data to be recovered from a corrupted debugger transfer
    // without repeating the original AP transfer.
    RESEND      = 0x8,

    // Write only
    // The SELECT register:
    // • Selects an Access Port (AP) and the active register banks within that AP.
    // • Selects the DP address bank.
    SELECT      = 0x8,

    // Read only
    // The RDBUFF register captures data from the AP, presented as the result of a previous read.
    RDBUFF      = 0xC
}


class SWDebugPort {

    _clkPin = null;
    _dataPin = null;

    // write = 0
    // read = 1
    _rwState = 0;

    _lastRead = null;

    constructor(clkPin, dataPin) {
        const SWDP_ACK_OK   = 1;
        const SWDP_ACK_WAIT = 2;
        const SWDP_ACK_FAIL = 4;

        const SWDP_RETRIES  = 3;
        // Delay before next retry in case of WAIT ack
        const SWDP_RETRY_DELAY = 0.0001;

        _clkPin = clkPin;
        _dataPin = dataPin;
    }

    function connect() {
        // Connection flow:
        // 1. Switch the line to SWD:
        //     - Reset the line (50+ HIGH bits)
        //     - Send the JTAG-to-SWD switch sequence
        // 2. Reset and take the connection out of reset state:
        //     - Reset the line (50+ HIGH bits)
        //     - Idle
        //     - Read DPIDR
        //     - Clear sticky bits

        const SWDP_JTAG_SWD_SEL = 0xE79E;
        const SWDP_JTAG_SWD_SEL_LEN = 16;

        logger.info("Connecting...", LOG_SOURCE.SWDP);

        _clkPin.configure(DIGITAL_OUT, 0);
        _dataPin.configure(DIGITAL_OUT, 0);

        _sendReset();

        _writeData(SWDP_JTAG_SWD_SEL, SWDP_JTAG_SWD_SEL_LEN);

        return resetLine();
    }

    function resetLine() {
        logger.info("Resetting the line...", LOG_SOURCE.SWDP);
        _sendReset();
        _idle();

        local err = 0;
        if (err = readDP(SWDP_REGISTER.DPIDR)) {
            return err;
        }

        logger.info(format("DP IDCODE = 0x%08x", getLastRead()), LOG_SOURCE.SWDP);

        return clearStickyBits();
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

    function clearStickyBits() {
        const SWDP_CLEAR_ALL_STICKY = 0x1E;

        return writeDP(SWDP_REGISTER.ABORT, SWDP_CLEAR_ALL_STICKY);
    }

    // apsel : 8bit, apbank : 4bit, dpbank : 4bit
    function select(apsel, apbank, dpbank = 0x0) {
        // The SELECT register:
        // • Selects an Access Port (AP) and the active register banks within that AP.
        // • Selects the DP address bank.

        local data = (apsel & 0xFF) << 24;
        data = data | ((apbank & 0x0F) << 4);
        data = data | (dpbank & 0x0F);

        return writeDP(SWDP_REGISTER.SELECT, data);
    }

    function getLastRead() {
        return _lastRead;
    }

    function _read(ap, addr) {
        // Write header |
        // Turnaround   |- Issue request
        // Ack          |
        // Read data
        // Read parity
        // Turnaround

        const SWDP_REQUEST_TYPE_READ = 1;

        logger.info(format("Read request: ap = 0x%01x addr = 0x%01x", ap, addr), LOG_SOURCE.SWDP);

        _lastRead = null;

        local header = _createHeader(ap, SWDP_REQUEST_TYPE_READ, addr);
        logger.debug(format("Header = 0x%02x", header), LOG_SOURCE.SWDP);

        local ack = _issueRequest(header);

        local err = _ackToError(ack);

        local parity = null;
        if (err == 0) {
            _lastRead = _readBits(32);
            parity = _readBits(1);
            logger.debug(format("Data = 0x%08x Parity = 0x%01x", _lastRead, parity), LOG_SOURCE.SWDP);

            if (parity != _parity(_lastRead)) {
                logger.error("Request failed with parity error", LOG_SOURCE.SWDP);
                err = SWDP_ERROR_PARITY;
                _lastRead = null;
            }
        }

        _trnToWrite();

        _idle();

        return err;
    }

    // data is a word (4B)
    function _write(ap, addr, data) {
        // Write header |
        // Turnaround   |- Issue request
        // Ack          |
        // Turnaround
        // Write data
        // Write parity

        const SWDP_REQUEST_TYPE_WRITE = 0;

        logger.info(format("Write request: ap = 0x%01x addr = 0x%01x data = 0x%08x", ap, addr, data), LOG_SOURCE.SWDP);

        local header = _createHeader(ap, SWDP_REQUEST_TYPE_WRITE, addr);
        logger.debug(format("Header = 0x%02x", header), LOG_SOURCE.SWDP);

        local ack = _issueRequest(header);

        local err = _ackToError(ack);

        _trnToWrite();

        if (err == 0) {
            _writeData(data, 32);
            _writeData(_parity(data), 1);
        }

        _idle();

        return err;
    }

    function _issueRequest(header) {
        local ack = null;
        local retries = 0;

        while (true) {
            _trnToWrite();

            _writeHeader(header);

            _trnToRead();

            ack = _ack();
            logger.debug(format("ACK = 0x%01x", ack), LOG_SOURCE.SWDP);

            if (ack == SWDP_ACK_WAIT && retries < SWDP_RETRIES) {
                logger.debug("Got WAIT ack. Retrying the request...", LOG_SOURCE.SWDP);
                imp.sleep(SWDP_RETRY_DELAY);
                retries++;
            } else {
                break;
            }
        }

        return ack;
    }

    function _ackToError(ack) {
        local err = 0;

        if (ack == SWDP_ACK_WAIT) {
            logger.error("Request timed out", LOG_SOURCE.SWDP);
            err = SWDP_ERROR_TIMEOUT;
        } else if (ack == SWDP_ACK_FAIL) {
            logger.error("Request failed with FAIL ack", LOG_SOURCE.SWDP);
            err = SWDP_ERROR_ACK_FAIL;
        } else if (ack != SWDP_ACK_OK) {
            logger.error("Request failed with invalid ack. It is probably a protocol error", LOG_SOURCE.SWDP);
            err = SWDP_ERROR_ACK_INVAL;
        }

        return err;
    }

    function _createHeader(ap, rw, addr) {
        // Header consists of 8 bits: [Start bit, AP/DP, R/W, Addr1, Addr2, Parity, Stop bit, Park bit]
        // Start bit = Park bit = 1
        // Stop bit = 0

        local parity = ap + rw + (addr >>> 3) + ((addr >>> 2) & 1);
        parity = parity & 1;

        // 0x81 = 0b10000001
        local header = 0x81;
        header = header | (ap << 6);
        header = header | (rw << 5);
        header = header | ((addr & 4) << 2);
        header = header | ((addr & 8));
        header = header | (parity << 2);

        return header;
    }

    // Writes a header MSB-first
    function _writeHeader(header) {
        for (local i = 0; i < 8; i++) {
            _dataPin.write(header & 0x80);
            _clkPin.write(1);
            _clkPin.write(0);
            header = header << 1;
        }
    }

    // Writes any arbitrary data (maximum 32 bits) LSB-first
    function _writeData(word, bitsNum = 32) {
        for (local i = 0; i < bitsNum; i++) {
            _dataPin.write(word & 0x1);
            _clkPin.write(1);
            _clkPin.write(0);
            word = word >>> 1;
        }
    }

    // Reads data (maximum 32 bits) LSB-first
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
        return _readBits(3);
    }

    function _trnToRead() {
        if (_rwState == 1) {
            return;
        }
        _dataPin.configure(DIGITAL_IN_PULLUP);
        _clkPin.write(1);
        _clkPin.write(0);
        _rwState = 1;
    }

    function _trnToWrite() {
        if (_rwState == 0) {
            return;
        }
        _clkPin.write(1);
        _clkPin.write(0);
        _dataPin.configure(DIGITAL_OUT, 0);
        _rwState = 0;
    }

    function _sendReset() {
        // 50 HIGH bits reset the line (+6 just in case)
        const SWDP_RESET_LINE_BITS_NUM = 56;

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

    function _parity(word) {
        local parity = 0;
        for (parity = 0; word != 0; parity = parity ^ 1) {
            word = word & (word - 1);
        }
        return parity;
    }
}
