// TODO: add a check for DBGMCU_IDCODE value (device's memory density)
class SWDSTM32 {

    _swdp = null;
    _swma = null;

    constructor(swDebugPort, swMemAP) {
        // Flash program and erase controller base address
        const SWDSTM32_FPEC_BASE_ADDR    = 0x40022000;
        const SWDSTM32_FLASH_KEYR_OFFSET = 0x04;
        const SWDSTM32_FLASH_SR_OFFSET   = 0x0C;
        const SWDSTM32_FLASH_CR_OFFSET   = 0x10;
        // Private peripheral bus base address
        const SWDSTM32_PPB_BASE_ADDR     = 0xE0000000;
        const SWDSTM32_DEBUG_HCSR_OFFSET = 0xEDF0;
        const SWDSTM32_APP_IRCR_OFFSET   = 0xED0C;

        const SWDSTM32_DBGKEY = 0xA05F0000;


        _swdp = swDebugPort;
        _swma = swMemAP;
    }

    function halt() {
        const SWDSTM32_C_HALT       = 0x00000002;
        const SWDSTM32_C_DEBUGEN    = 0x00000001;

        local haltCmd = SWDSTM32_DBGKEY | SWDSTM32_C_HALT | SWDSTM32_C_DEBUGEN;
        _swma.writeWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_HCSR_OFFSET, haltCmd);

        // TODO: make halt-on-reset (to make sure all peripherals are in known state)
    }

    function unhalt() {
        _swma.writeWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_DEBUG_HCSR_OFFSET, SWDSTM32_DBGKEY);
    }

    function sysReset() {
        const SWDSTM32_VECTKEY      = 0x05FA0000;
        const SWDSTM32_SYSRESETREQ  = 0x00000004;

        local resetCmd = SWDSTM32_VECTKEY | SWDSTM32_SYSRESETREQ;
        _swma.writeWord(SWDSTM32_PPB_BASE_ADDR + SWDSTM32_APP_IRCR_OFFSET, resetCmd);
    }

    function flashUnlock() {
        const SWDSTM32_FLASH_UNLOCK_KEY1 = 0x45670123;
        const SWDSTM32_FLASH_UNLOCK_KEY2 = 0xCDEF89AB;

        _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_KEYR_OFFSET, SWDSTM32_FLASH_UNLOCK_KEY1);
        _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_KEYR_OFFSET, SWDSTM32_FLASH_UNLOCK_KEY2);
    }

    function flashErase() {
        // const SWDSTM32_OPTWRE   = 0x00000200;
        const SWDSTM32_MER  = 0x00000004;
        const SWDSTM32_STRT = 0x00000040;

        _wait();

        _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_MER);
        _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_MER | SWDSTM32_STRT);

        _wait();

        // TODO: not needed?
        // _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, 0x00000200);
    }

    function flashProgram() {
        // const SWDSTM32_OPTWRE   = 0x00000200;
        const SWDSTM32_PG = 0x00000001;

        _wait();
        _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_PG);
    }

    function flashProgramEnd() {
        // const SWDSTM32_OPTWRE   = 0x00000200;

        // _swma.writeWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_CR_OFFSET, SWDSTM32_OPTWRE);
    }

    function _wait() {
        while (_bsyBit() == 1) {
            server.log("Erasing in progress...");
            imp.sleep(0.01);
        }
    }

    function _bsyBit() {
        const SWDSTM32_BSY_BIT_MASK = 0x00000001;

        return _swma.readWord(SWDSTM32_FPEC_BASE_ADDR + SWDSTM32_FLASH_SR_OFFSET)[1] & SWDSTM32_BSY_BIT_MASK;
    }

}
