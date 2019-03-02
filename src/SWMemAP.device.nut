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

const SWMA_ERROR_INIT_TIMEOUT = -100;

const SWMA_SIZE_WORD = 4;
const SWMA_SIZE_HALFWORD = 2;

// Docs: ARM IHI0031D (https://static.docs.arm.com/ihi0031/d/debug_interface_v5_2_architecture_specification_IHI0031D.pdf)

enum SWMA_REGISTER {
    // Read/Write
    // CSW (Control/Status Word register) configures and controls accesses through the MEM-AP to or from a connected memory system
    CSW = 0x00,

    // Read/Write
    // TAR (Transfer Address Register) holds the memory (to which the MEM-AP is connected) address to be accessed through AP accesses.
    TAR = 0x04,

    // Read/Write
    // Data Read/Write (DRW) register maps the value that is passed in an AP access directly to one or more memory accesses
    // at the address that is specified in the TAR.
    // The value depends on the access mode:
    // • In write mode, DRW holds the value to write for the current transfer to the address specified in the TAR.
    // • In read mode, DRW holds the value that is read in the current transfer from the address that is specified in the TAR.
    // The AP access does not complete until the memory access, or accesses, complete
    DRW = 0x0C,

    // Read only
    // IDR identifies the Access Port. An IDR value of zero indicates that there is no AP present.
    IDR = 0xFC
}


class SWMemAP {

    _swdp = null;
    _lastRead = null;

    constructor(swDebugPort) {
        _swdp = swDebugPort;
    }

    function init() {
        // System powerup request
        const SWMA_CTRL_CSYSPWRUPREQ = 0x40000000;
        // Debug powerup request
        const SWMA_CTRL_CDBGPWRUPREQ = 0x10000000;
        // Debug reset request
        const SWMA_CTRL_CDBGRSTREQ   = 0x04000000;
        // System powerup acknowledge
        const SWMA_CTRL_CSYSPWRUPACK = 0x80000000;
        // Debug powerup acknowledge
        const SWMA_CTRL_CDBGPWRUPACK = 0x20000000;
        // Debug reset acknowledge
        const SWMA_CTRL_CDBGRSTACK   = 0x08000000;

        // Sec
        const SWMA_CHECK_DELAY       = 0.001;
        // Millis
        const SWMA_POWERUP_TIMEOUT   = 1000;
        // Mem-AP's AP number is 0
        const SWMA_AP_NUM            = 0;


        logger.info("Powering up the system and debug domains. And resetting the debug domain...", LOG_SOURCE.SWMA);

        local err = _swdp.writeDP(SWDP_REGISTER.CTRL_STAT, SWMA_CTRL_CSYSPWRUPREQ | SWMA_CTRL_CDBGPWRUPREQ | SWMA_CTRL_CDBGRSTREQ);

        if (err) {
            logger.error("Failed to power up the system and debug domains: " + err, LOG_SOURCE.SWMA);
            return err;
        }

        local ready = false;
        local startTime = hardware.millis();
        while (!ready) {
            imp.sleep(SWMA_CHECK_DELAY);

            if (err = _swdp.readDP(SWDP_REGISTER.CTRL_STAT)) {
                logger.error("Failed to read DP status: " + err, LOG_SOURCE.SWMA);
                return err;
            }

            ready = _swdp.getLastRead() & (SWMA_CTRL_CSYSPWRUPREQ | SWMA_CTRL_CDBGPWRUPREQ | SWMA_CTRL_CDBGRSTREQ);

            if (hardware.millis() - startTime > SWMA_POWERUP_TIMEOUT) {
                return SWMA_ERROR_INIT_TIMEOUT;
            }
        }

        if (err = read(SWMA_REGISTER.IDR)) {
            logger.error("Failed to read IDCODE: " + err, LOG_SOURCE.SWMA);
            return err;
        }
        logger.info(format("Mem-AP IDCODE = 0x%08x", _lastRead), LOG_SOURCE.SWMA);

        return 0;
    }

    // Returns the result of the last read operation (read/memRead/memReadWord)
    function getLastRead() {
        return _lastRead;
    }

    // Reads the specified register and stores its data (integer) to the _lastRead buffer
    function read(addr) {
        // 1. Set the correct AP and APBANK in the SELECT register (first 4 bits of `addr`)
        // 2. Read the register of MEM-AP with the specified address (last 4 bits of `addr`)
        // 3. Read the RDBUFF register of DP (as any AP read operation stores its result to the RDBUFF)

        local err = _swdp.select(SWMA_AP_NUM, (addr & 0xF0) >> 4) || _swdp.readAP(addr & 0x0F) || _swdp.readDP(SWDP_REGISTER.RDBUFF);

        if (err) {
            logger.error("Failed to read Mem-AP register: " + err, LOG_SOURCE.SWMA);
        } else {
            _lastRead = _swdp.getLastRead();
        }

        return err;
    }

    // Writes data (integer) to the specified register
    function write(addr, data) {
        // 1. Set the correct AP and APBANK in the SELECT register (first 4 bits of `addr`)
        // 2. Write to the register of MEM-AP with the specified address (last 4 bits of `addr`)

        local err = _swdp.select(SWMA_AP_NUM, (addr & 0xF0) >> 4) || _swdp.writeAP(addr & 0x0F, data);

        if (err) {
            logger.error("Failed to write Mem-AP register: " + err, LOG_SOURCE.SWMA);
        }

        return err;
    }

    // Reads the memory and stores the data (blob) to the _lastRead buffer
    //
    // Count is a number of words (4B) to read. A word can be read with one or more accesses (packed transfers).
    // accessSize defines the size of each access and thus the number of accesses per read of word.
    // For example: accessSize = SWMA_SIZE_HALFWORD (= 2); in this case the Mem-AP will make two accesses (2B + 2B) to read a word (4B)
    // Addr must be aligned appropriately with respect to accessSize (e.g. for accessSize = SWMA_SIZE_WORD the addr should be aligned at 4B bound)
    function memRead(addr, count, accessSize = SWMA_SIZE_WORD) {
        // We are going to set the SELECT register of DP manually (instead of using read() method which does it by itself)
        // This will increase speed because we don't do extra accesses to the SELECT register on every read
        local drwSelectApbank = (SWMA_REGISTER.DRW & 0xF0) >> 4;
        local drwOffset = SWMA_REGISTER.DRW & 0x0F;

        local data = blob();
        local curAddr = addr;
        local next1KBbound = 0;
        local err = 0;

        for (local i = 0; i < count; i++) {
            // Automatic address increment is only guaranteed to operate on the 10 least significant bits of the address that is held in the TAR
            // So we should set manually the address in the TAR at every 1KB bound
            // Also we do _memAccessSetup() before the first read operation (when curAddr == addr)
            if (curAddr == addr || curAddr >= next1KBbound) {
                // We use auto-increment feature
                if (err = _memAccessSetup(curAddr, accessSize, true)) {
                    return err;
                }
                next1KBbound = (curAddr & 0xFFFFFC00) + 1024;

                // Here we set the SELECT register of DP. We do it once for all reads within 1KB range
                // The other calls like _memAccessSetup() and memReadWord() can change the content of the SELECT register so
                // we must set it to the correct value after those calls
                _swdp.select(SWMA_AP_NUM, drwSelectApbank);
            }

            // The case when addr is not aligned at 4B bound and a read operation starts before a 1KB bound and ends after it
            // For example: curAddr = 0x080003FE (2 bytes before 1KB bound); in this case we are going to read 2 bytes
            // before 1KB bound (0x08000400) and 2 bytes after it. But automatic address increment doesn't guarantee switches over 1KB bound (see above).
            // So we need to read these 4B (word) manually and then we can continue to use the automatic address increment feature.
            if (next1KBbound - curAddr < SWMA_SIZE_WORD) {
                if (err = memReadWord(curAddr, accessSize)) {
                    return err;
                }

                data.writen(_lastRead, 'i');

            } else if (err = _swdp.readAP(drwOffset) || _swdp.readDP(SWDP_REGISTER.RDBUFF)) {
                return err;
            } else {
                // _swdp.readAP() and _swdp.readDP() finished successfully

                // We use _swdp.getLastRead() while working with _swdp directly (_swdp.readAP() and _swdp.readDP() calls above)
                data.writen(_swdp.getLastRead(), 'i');
            }

            // No matter what the accessSize is, we read 4B per one operation
            curAddr += SWMA_SIZE_WORD;
        }

        data.seek(0);
        _lastRead = data;

        return 0;
    }

    // Writes data (blob) to the memory
    //
    // A word can be written with one or more accesses (packed transfers).
    // accessSize defines the size of each access and thus the number of accesses per write of word.
    // For example: accessSize = SWMA_SIZE_HALFWORD (= 2); in this case the Mem-AP will make two accesses (2B + 2B) to write a word (4B)
    // Addr must be aligned appropriately with respect to accessSize (e.g. for accessSize = SWMA_SIZE_WORD the addr should be aligned at 4B bound)
    // Size of data (blob) must be a multiple of 4
    function memWrite(addr, data, accessSize = SWMA_SIZE_WORD) {
        if (data.len() & 0x3) {
            throw "Size of data must be a multiple of 4";
        }
        data.seek(0);

        // We are going to set the SELECT register of DP manually (instead of using write() method which does it by itself)
        // This will increase speed because we don't do extra accesses to the SELECT register on every write
        local drwSelectApbank = (SWMA_REGISTER.DRW & 0xF0) >> 4;
        local drwOffset = SWMA_REGISTER.DRW & 0x0F;

        local curAddr = addr;
        local next1KBbound = 0;
        local err = 0;

        for (local i = 0; i < data.len() / 4; i++) {
            // Automatic address increment is only guaranteed to operate on the 10 least significant bits of the address that is held in the TAR
            // So we should set manually the address in the TAR at every 1KB bound
            // Also we do _memAccessSetup() before the first write operation (when curAddr == addr)
            if (curAddr == addr || curAddr >= next1KBbound) {
                // We use auto-increment feature
                if (err = _memAccessSetup(curAddr, accessSize, true)) {
                    return err;
                }
                next1KBbound = (curAddr & 0xFFFFFC00) + 1024;

                // Here we set the SELECT register of DP. We do it once for all writes within 1KB range
                // The other calls like _memAccessSetup() and memWriteWord() can change the content of the SELECT register so
                // we must set it to the correct value after those calls
                _swdp.select(SWMA_AP_NUM, drwSelectApbank);
            }

            // The case when addr is not aligned at 4B bound and a write operation starts before a 1KB bound and ends after it
            // For example: curAddr = 0x080003FE (2 bytes before 1KB bound); in this case we are going to write 2 bytes
            // before 1KB bound (0x08000400) and 2 bytes after it. But automatic address increment doesn't guarantee switches over 1KB bound (see above).
            // So we need to write these 4B (word) manually and then we can continue to use the automatic address increment feature.
            if (next1KBbound - curAddr < SWMA_SIZE_WORD) {
                if (err = memWriteWord(curAddr, data.readn('i'), accessSize)) {
                    return err;
                }
            } else if (err = _swdp.writeAP(drwOffset, data.readn('i'))) {
                return err;
            }

            // No matter what the accessSize is, we write 4B per one operation
            curAddr += SWMA_SIZE_WORD;
        }

        data.seek(0);

        return 0;
    }

    // Reads a word (4B) from the memory and stores the data (integer) to the _lastRead buffer
    //
    // A word can be read with one or more accesses (packed transfers).
    // accessSize defines the size of each access and thus the number of accesses per read of word.
    // For example: accessSize = SWMA_SIZE_HALFWORD (= 2); in this case the Mem-AP will make two accesses (2B + 2B) to read a word (4B)
    // Addr must be aligned appropriately with respect to accessSize (e.g. for accessSize = SWMA_SIZE_WORD the addr should be aligned at 4B bound)
    function memReadWord(addr, accessSize = SWMA_SIZE_WORD) {
        switch (accessSize) {
            case SWMA_SIZE_WORD:
                return _memAccessSetup(addr, SWMA_SIZE_WORD) ||
                       read(SWMA_REGISTER.DRW);

            case SWMA_SIZE_HALFWORD:
                local err = 0;
                if (err = _memReadHalfWord(addr)) {
                    return err;
                }

                local halfWord = _lastRead & 0xFFFF0000;

                if (err = _memReadHalfWord(addr + SWMA_SIZE_HALFWORD)) {
                    return err;
                }

                _lastRead = halfWord | (_lastRead & 0x0000FFFF);
                return 0;
            default:
                throw "Unknown memory access size";
                break;
        }
    }

    // Writes 4B of data (integer) to the memory
    //
    // A word can be written with one or more accesses (packed transfers).
    // accessSize defines the size of each access and thus the number of accesses per write of word.
    // For example: accessSize = SWMA_SIZE_HALFWORD (= 2); in this case the Mem-AP will make two accesses (2B + 2B) to write a word (4B)
    // Addr must be aligned appropriately with respect to accessSize (e.g. for accessSize = SWMA_SIZE_WORD the addr should be aligned at 4B bound)
    function memWriteWord(addr, data, accessSize = SWMA_SIZE_WORD) {
        switch (accessSize) {
            case SWMA_SIZE_WORD:
                return _memAccessSetup(addr, SWMA_SIZE_WORD) ||
                       write(SWMA_REGISTER.DRW, data);

            case SWMA_SIZE_HALFWORD:
                local err = 0;
                if (err = _memWriteHalfWord(addr, data)) {
                    return err;
                }

                if (err = _memWriteHalfWord(addr + SWMA_SIZE_HALFWORD, data)) {
                    return err;
                }
                break;
            default:
                throw "Unknown memory access size";
                break;
        }

        return 0;
    }

    function _memReadHalfWord(addr) {
        return _memAccessSetup(addr, SWMA_SIZE_HALFWORD) ||
               read(SWMA_REGISTER.DRW);
    }

    function _memWriteHalfWord(addr, data) {
        return _memAccessSetup(addr, SWMA_SIZE_HALFWORD) ||
               write(SWMA_REGISTER.DRW, data);
    }

    function _memAccessSetup(addr, size = SWMA_SIZE_WORD, autoIncrement = false) {
        // Docs: Automatic address increment - p.C2-152 IHI0031D
        // Docs: Access size for memory accesses - p.C2-156 IHI0031D

        const SWMA_CSW_SIZE_WORD     = 0x00000002;
        const SWMA_CSW_SIZE_HALFWORD = 0x00000001;
        const SWMA_AUTO_INCR_SINGLE  = 0x00000010;
        const SWMA_AUTO_INCR_PACKED  = 0x00000020;

        local err = 0;

        if (err = read(SWMA_REGISTER.CSW)) {
            logger.error("Memory access setup failed. Can't read CSW register: " + err, LOG_SOURCE.SWMA);
            return err;
        }
        local csw = _swdp.getLastRead() & 0xFFFFFF00;

        switch (size) {
            case SWMA_SIZE_WORD:
                csw = csw | SWMA_CSW_SIZE_WORD;
                if (autoIncrement) {
                    csw = csw | SWMA_AUTO_INCR_SINGLE;
                }
                break;
            case SWMA_SIZE_HALFWORD:
                csw = csw | SWMA_CSW_SIZE_HALFWORD;
                if (autoIncrement) {
                    csw = csw | SWMA_AUTO_INCR_PACKED;
                }
                break;
            default:
                throw "Unknown memory access size";
                break;
        }
        // TODO: Implement the other access sizes (?)

        // Write the new value into the CSW register
        if (err = write(SWMA_REGISTER.CSW, csw)) {
            logger.error("Memory access setup failed. Can't write CSW register: " + err, LOG_SOURCE.SWMA);
            return err;
        }
        // Write the address into the TAR register
        if (err = write(SWMA_REGISTER.TAR, addr)) {
            logger.error("Memory access setup failed. Can't write TAR register: " + err, LOG_SOURCE.SWMA);
            return err;
        }

        return 0;
    }

}
