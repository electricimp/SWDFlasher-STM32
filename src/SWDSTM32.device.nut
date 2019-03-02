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

const SWDSTM32_ERROR_OP_NOT_ALLOWED = -1000;
const SWDSTM32_ERROR_TIMEOUT = -1001;

// Docs: ARM DDI0403E.c (https://static.docs.arm.com/ddi0403/ec/DDI0403E_c_armv7m_arm.pdf)
// Docs: ST PM0063 (https://www.st.com/resource/en/programming_manual/cd00246875.pdf)


class SWDSTM32 {

    _swdp = null;
    _swma = null;

    // contains `null` if programming is not in progress
    // otherwise the current address to write the firmware
    _curProgAddr = null;

    constructor(swDebugPort, swMemAP) {
        // # Cortex-M3-specific constants #

        // Private peripheral bus base address
        const SWDSTM32_PPB_BASE_ADDR     = 0xE0000000;
        // Debug Halting Control and Status Register
        // Controls Halting debug
        const SWDSTM32_DEBUG_HCSR_OFFSET = 0xEDF0;
        // Debug Exception and Monitor Control Register
        // Manages vector catch behavior and DebugMonitor handling when debugging
        const SWDSTM32_DEBUG_EMCR_OFFSET = 0xEDFC;
        // Application Interrupt and Reset Control Register
        const SWDSTM32_APP_IRCR_OFFSET   = 0xED0C;

        const SWDSTM32_DBGKEY = 0xA05F0000;

        // # STM32F1-specific constants #

        // Flash program and erase controller base address
        const SWDSTM32_FPEC_BASE_ADDR    = 0x40022000;
        // FPEC key register
        const SWDSTM32_FLASH_KEYR_OFFSET = 0x04;
        // Flash status register
        const SWDSTM32_FLASH_SR_OFFSET   = 0x0C;
        // Flash control register
        const SWDSTM32_FLASH_CR_OFFSET   = 0x10;


        _swdp = swDebugPort;
        _swma = swMemAP;
    }

    function connect() {
        return _swdp.connect() ||
               _swma.init();
    }

    function halt() {
        const SWDSTM32_C_HALT       = 0x00000002;
        const SWDSTM32_C_DEBUGEN    = 0x00000001;

        logger.info("Halting the core...", LOG_SOURCE.SWDSTM32);

        local haltCmd = SWDSTM32_DBGKEY | SWDSTM32_C_HALT | SWDSTM32_C_DEBUGEN;

        return _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_HCSR_OFFSET, haltCmd);
    }

    function unhalt() {
        logger.info("Unhalting the core...", LOG_SOURCE.SWDSTM32);

        return _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_HCSR_OFFSET, SWDSTM32_DBGKEY);
    }

    function enableHaltOnReset() {
        const SWDSTM32_C_DEBUGEN    = 0x00000001;
        const SWDSTM32_VC_CORERESET = 0x00000001;

        logger.info("Enabling halt-on-reset...", LOG_SOURCE.SWDSTM32);

        return _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_HCSR_OFFSET, SWDSTM32_DBGKEY | SWDSTM32_C_DEBUGEN) ||
               _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_EMCR_OFFSET, SWDSTM32_VC_CORERESET);
    }

    function disableHaltOnReset() {
        logger.info("Disabling halt-on-reset...", LOG_SOURCE.SWDSTM32);

        return _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_EMCR_OFFSET, 0);
    }

    function sysReset() {
        const SWDSTM32_VECTKEY      = 0x05FA0000;
        const SWDSTM32_SYSRESETREQ  = 0x00000004;

        logger.info("System reset...", LOG_SOURCE.SWDSTM32);

        local resetCmd = SWDSTM32_VECTKEY | SWDSTM32_SYSRESETREQ;
        return _swma.memWriteWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_APP_IRCR_OFFSET, resetCmd);
    }

    function flashUnlock() {
        const SWDSTM32_FLASH_UNLOCK_KEY1 = 0x45670123;
        const SWDSTM32_FLASH_UNLOCK_KEY2 = 0xCDEF89AB;

        logger.info("Unlocking the flash...", LOG_SOURCE.SWDSTM32);

        return _swma.memWriteWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_KEYR_OFFSET, SWDSTM32_FLASH_UNLOCK_KEY1) ||
               _swma.memWriteWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_KEYR_OFFSET, SWDSTM32_FLASH_UNLOCK_KEY2);
    }

    function flashErase() {
        const SWDSTM32_MER  = 0x00000004;
        const SWDSTM32_STRT = 0x00000040;

        logger.info("Erasing the flash...", LOG_SOURCE.SWDSTM32);

        return _wait() ||
               _swma.memWriteWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_MER) ||
               _swma.memWriteWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_MER | SWDSTM32_STRT) ||
               _wait();
    }

    function beginProgramming() {
        const SWDSTM32_PG = 0x00000001;
        const SWDSTM32_FW_START_ADDR = 0x08000000;

        if (_curProgAddr != null) {
            logger.error("Programming is already in progress!", LOG_SOURCE.SWDSTM32);
            return SWDSTM32_ERROR_OP_NOT_ALLOWED;
        }

        logger.info("Begin programming", LOG_SOURCE.SWDSTM32);

        local err = _wait() || _swma.memWriteWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_PG);
        if (err) {
            return err;
        }

        _curProgAddr = SWDSTM32_FW_START_ADDR;

        return 0;
    }

    // data (blob) is a firmware (or a part of it)
    // This method must be called only after startProgramming() and before endProgramming()
    // and may be called several times - this will append the data
    // Size of data (blob) must be a multiple of 4
    function program(data) {
        if (_curProgAddr == null) {
            logger.error("Programming is not started", LOG_SOURCE.SWDSTM32);
            return SWDSTM32_ERROR_OP_NOT_ALLOWED;
        }

        logger.info("Programming...", LOG_SOURCE.SWDSTM32);

        local err = _swma.memWrite(_curProgAddr, data, SWMA_SIZE_HALFWORD);
        if (err) {
            return err;
        }

        _curProgAddr += data.len();

        return 0;
    }

    // Returns the current status of programming: true if it is in progress, false otherwise
    function isBeingProgrammed() {
        return _curProgAddr != null;
    }

    function endProgramming() {
        if (_curProgAddr == null) {
            return SWDSTM32_ERROR_OP_NOT_ALLOWED;
        }
        _curProgAddr = null;

        logger.info("Ending the programming...", LOG_SOURCE.SWDSTM32);

        return _wait();
    }

    function _wait() {
        // Sec
        const SWDSTM32_BSY_CHECK_DELAY = 0.001;
        // Millis
        const SWDSTM32_BSY_TIMEOUT = 1000;

        local startTime = hardware.millis();
        local bsyBit = 0;
        while ((bsyBit = _bsyBit()) > 0) {
            imp.sleep(SWDSTM32_BSY_CHECK_DELAY);
            if (hardware.millis() - startTime > SWDSTM32_BSY_TIMEOUT) {
                return SWDSTM32_ERROR_TIMEOUT;
            }
        }

        return bsyBit;
    }

    function _bsyBit() {
        const SWDSTM32_BSY_BIT_MASK = 0x00000001;

        return _swma.memReadWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_SR_OFFSET) ||
               (_swma.getLastRead() & SWDSTM32_BSY_BIT_MASK);
    }

}
